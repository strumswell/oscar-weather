//
//  OscarRadarState.swift
//  Oscar°
//
//  Timeline state for the live radar layer: metadata + frame grid loading,
//  playback and scrubbing.
//

import Foundation
import Observation
import UIKit
import os

@MainActor
@Observable
final class OscarRadarState {
    // nil slots represent frames whose image hasn't arrived yet.
    // The array is pre-sized to the full frame count as soon as metadata loads.
    var frames: [OscarRadarFrame?] = []

    // Populated from metadata immediately — lets us show the scrubber skeleton
    // and compute the live-frame index before any images have downloaded.
    private(set) var frameTimestamps: [String] = []

    var bounds: OscarRadarBounds?
    /// Per-pair motion fields for morph rendering (`/radar/{region}/motion`), fetched
    /// alongside the frame metadata. nil until loaded (the layer falls back to a plain
    /// data-space cross-fade, so nothing waits on this).
    private(set) var motion: RadarMotionData?
    /// Active radar coverage (DWD Germany / OPERA Europe / MRMS USA). Use `setRegion(_:)`
    /// to change it — it clears loaded frames so the next load re-fetches.
    private(set) var region: RadarRegion = .germany
    var isLoading: Bool = false
    var currentFrameIndex: Int = 0 {
        didSet {
            guard currentFrameIndex != oldValue else { return }
            handleFrameSelectionChanged()
        }
    }
    var isPlaying: Bool = false
    var error: String?
    private(set) var loadingFrameIndices: Set<Int> = []
    // Stored (not derived from `frames`) — it's read in the per-frame-load hot path
    // and rebuilding a Set per read made every load O(frame count).
    private(set) var loadedFrameIndices: Set<Int> = []
    private(set) var renderFrameIndex: Int?
    private(set) var interactionState: MapInteractionState = .idle
    private(set) var isMapInteracting = false

    @ObservationIgnored private let playback = PlaybackTicker()
    @ObservationIgnored private var frameInfos: [RadarFrameInfo] = []
    @ObservationIgnored private var frameDates: [Date?] = []
    @ObservationIgnored private var loadSessionID = UUID()
    @ObservationIgnored private var suppressSelectionSideEffects = false
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundPreloadTask: Task<Void, Never>?
    @ObservationIgnored private var focusedLoadTask: Task<Void, Never>?
    @ObservationIgnored private var lastMetadataLoad: Date?
    private static let metadataStaleAfter: TimeInterval = 10 * 60
    // Live instances (they come and go with their views) for the app-level
    // memory-warning purge.
    private static let instances = NSHashTable<OscarRadarState>.weakObjects()

    init() {
        Self.instances.add(self)
    }

    // MARK: - Derived state

    var currentFrame: OscarRadarFrame? {
        frame(at: renderFrameIndex ?? currentFrameIndex)
    }

    var nextFrame: OscarRadarFrame? {
        guard let anchor = renderFrameIndex ?? (isSelectedFrameReady ? currentFrameIndex : nil) else { return nil }
        let loaded = frames.map { $0 != nil }
        guard let nextIndex = nextLoadedIndex(in: loaded, after: anchor) else { return nil }
        return frame(at: nextIndex)
    }

    /// Timestamp for the current position, even if the image isn't loaded yet.
    var currentFrameTimestamp: String? {
        guard currentFrameIndex < frameTimestamps.count else { return nil }
        return frameTimestamps[currentFrameIndex]
    }

    /// True only when the selected position is the frame closest to real time.
    /// Deliberately not a threshold check — only the "natural now" frame is LIVE.
    var isCurrentFrameLive: Bool {
        guard !frameDates.isEmpty else { return false }
        return currentFrameIndex == closestTimestampIndex(in: frameDates)
    }

    var hasAnyLoadedFrame: Bool {
        frames.contains { $0 != nil }
    }

    var isSelectedFrameReady: Bool {
        frames.indices.contains(currentFrameIndex) && frames[currentFrameIndex] != nil
    }

    // MARK: - Grid residency

    // Decoded grids are 1 byte/px (DWD ≈ 1.3 MB, OPERA ≈ 2 MB, MRMS ≈ 6 MB per frame),
    // so only a window around the selection stays resident; evicted slots go back to
    // nil and reload on demand via the normal loader (same UX as a not-yet-loaded
    // frame). The window is sized from the process's real memory headroom — a fixed
    // ±8 frames capped the radar preload at ±40 min and left the scrubber's far ticks
    // permanently unloaded; on today's devices the entire timeline usually fits.
    private static let gridResidencyBudget = adaptiveCacheBudget(
        fraction: 0.16, floor: 64 * 1024 * 1024, cap: 512 * 1024 * 1024)

    private var residencyRadius: Int {
        let bytesPerFrame = frames.lazy.compactMap { $0 }
            .map { max(1, $0.gridPayload.width * $0.gridPayload.height) }
            .max() ?? 4_000_000
        return max(8, Self.gridResidencyBudget / bytesPerFrame / 2)
    }

    private func residentFrameIndices(around center: Int) -> Set<Int> {
        let count = frames.count
        let radius = residencyRadius
        guard count > 2 * radius + 1 else { return Set(frames.indices) }
        // Modulo window so playback wrap-around (last frame → first) stays warm.
        var resident = Set((center - radius...center + radius)
            .map { (($0 % count) + count) % count })
        if !frameDates.isEmpty {
            resident.insert(closestTimestampIndex(in: frameDates))
        }
        if let renderFrameIndex {
            resident.insert(renderFrameIndex)
        }
        return resident
    }

    private func evictFrames(outside resident: Set<Int>) {
        for index in frames.indices where frames[index] != nil && !resident.contains(index) {
            frames[index] = nil
            loadedFrameIndices.remove(index)
        }
    }

    /// App-level memory-warning hook: drop every decoded grid except the displayed
    /// pair. Evicted frames reload on demand, exactly like not-yet-loaded ones.
    static func purgeDecodedGrids() {
        for state in instances.allObjects {
            state.backgroundPreloadTask?.cancel()
            let anchor = state.renderFrameIndex ?? state.currentFrameIndex
            var keep: Set<Int> = [anchor]
            if let next = nextLoadedIndex(in: state.frames.map { $0 != nil }, after: anchor) {
                keep.insert(next)
            }
            state.evictFrames(outside: keep)
        }
    }

    // MARK: - Region

    /// Switches radar coverage. Clears the loaded frames + in-flight work so the
    /// next `loadAllFrames()` fetches the new region. No-op
    /// if the region is unchanged.
    func setRegion(_ newRegion: RadarRegion) {
        guard newRegion != region else { return }
        region = newRegion
        resetForSourceChange()
    }

    private func resetForSourceChange() {
        bootstrapTask?.cancel()
        focusedLoadTask?.cancel()
        backgroundPreloadTask?.cancel()
        pause()

        loadSessionID = UUID()
        lastMetadataLoad = nil
        suppressSelectionSideEffects = true
        frames = []
        frameInfos = []
        frameTimestamps = []
        frameDates = []
        bounds = nil
        motion = nil
        loadingFrameIndices.removeAll()
        loadedFrameIndices.removeAll()
        renderFrameIndex = nil
        currentFrameIndex = 0
        suppressSelectionSideEffects = false
    }

    func reloadForCurrentRegion() async {
        await loadAllFrames()
    }

    /// Reload only when the shared metadata cache has expired (or nothing ever
    /// loaded, e.g. the last attempt failed offline) — the foreground/periodic
    /// refresh hook. A quick app switch stays a no-op; a return after the cache
    /// window re-fetches the frame list so the map doesn't keep replaying stale
    /// frames as "live".
    func refreshIfStale() async {
        guard !isLoading else { return }
        if hasAnyLoadedFrame, let lastMetadataLoad,
           Date().timeIntervalSince(lastMetadataLoad) < Self.metadataStaleAfter {
            return
        }
        await reloadForCurrentRegion()
    }

    // MARK: - Loading

    /// Loads all frames, showing the scrubber skeleton immediately after metadata
    /// arrives and filling in ticks progressively as each image downloads.
    func loadAllFrames() async {
        await loadFrames(allowBackgroundPreload: allowsBackgroundPreload())
    }

    // MARK: - Playback

    func play() {
        guard hasAnyLoadedFrame else { return }
        isPlaying = true
        interactionState = .playing
        restartBackgroundPreloadIfNeeded()
        playback.start(interval: .milliseconds(500)) { [weak self] in self?.advanceFrame() }
    }

    func pause() {
        isPlaying = false
        interactionState = .idle
        playback.stop()
    }

    /// Stops the internal ticker without changing `isPlaying`.
    /// Called when the Metal display link takes over frame advancement.
    func cancelInternalTimer() {
        playback.stop()
    }

    /// Advance to the next loaded frame. Called by the Metal display-link tick.
    func advanceFrame() {
        guard !frames.isEmpty else { return }
        let loaded = frames.map { $0 != nil }
        guard let next = nextLoadedIndex(in: loaded, after: currentFrameIndex) else {
            return
        }
        currentFrameIndex = next
    }

    func beginScrubbing() {
        interactionState = .scrubbing
        backgroundPreloadTask?.cancel()
    }

    func endScrubbing() {
        interactionState = isPlaying ? .playing : .idle
        restartBackgroundPreloadIfNeeded()
    }

    func beginMapInteraction() {
        guard !isMapInteracting else { return }
        isMapInteracting = true
        backgroundPreloadTask?.cancel()
    }

    func endMapInteraction() {
        guard isMapInteracting else { return }
        isMapInteracting = false
        restartBackgroundPreloadIfNeeded()
    }

    // MARK: - Private Helpers

    private func loadFrames(allowBackgroundPreload: Bool) async {
        bootstrapTask?.cancel()
        focusedLoadTask?.cancel()
        backgroundPreloadTask?.cancel()

        let sessionID = UUID()
        loadSessionID = sessionID
        isLoading = true
        error = nil
        loadingFrameIndices.removeAll()
        renderFrameIndex = nil

        bootstrapTask = Task { [weak self] in
            guard let self else { return }

            do {
                let (allFrameInfos, boundsInfo) = try await Self.fetchFrameInfos(region: self.region)
                guard !Task.isCancelled, self.loadSessionID == sessionID else { return }
                // Deep-past observation frames add little and eat preload/residency
                // budget — keep ~25 min of past plus the entire nowcast.
                let pastCutoff = Date().addingTimeInterval(-25 * 60)
                let fetchedFrameInfos = allFrameInfos.filter { info in
                    guard let date = parseFrameDate(info.timestamp) else { return true }
                    return date >= pastCutoff
                }
                guard !fetchedFrameInfos.isEmpty else {
                    self.isLoading = false
                    return
                }

                let timestamps = fetchedFrameInfos.map(\.timestamp)
                let dates = timestamps.map(parseFrameDate)
                let closest = closestTimestampIndex(in: dates)

                self.suppressSelectionSideEffects = true
                self.bounds = boundsInfo.asDomain
                self.frameInfos = fetchedFrameInfos
                self.frameTimestamps = timestamps
                self.frameDates = dates
                self.frames = Array(repeating: nil, count: fetchedFrameInfos.count)
                self.loadedFrameIndices = []
                self.currentFrameIndex = closest
                self.suppressSelectionSideEffects = false
                self.lastMetadataLoad = Date()

            // Motion fields load in parallel and are optional — the layer renders a
            // plain cross-fade until they arrive.
                let motionRegion = self.region
                Task { [weak self] in
                    let data = await Self.fetchMotionData(region: motionRegion)
                    guard let self, self.loadSessionID == sessionID else { return }
                    self.motion = data
                }

                await self.loadFocusedFrames(around: closest, sessionID: sessionID)

                guard !Task.isCancelled, self.loadSessionID == sessionID else { return }
                self.isLoading = false

                if allowBackgroundPreload {
                    self.restartBackgroundPreloadIfNeeded()
                }
            } catch {
                guard self.loadSessionID == sessionID else { return }
                self.error = String(localized: "Fehler beim Laden: \(error.localizedDescription)")
                self.isLoading = false
            }
        }

        await bootstrapTask?.value
    }

    private func handleFrameSelectionChanged() {
        guard !suppressSelectionSideEffects else { return }
        guard !frameInfos.isEmpty, frameInfos.indices.contains(currentFrameIndex) else { return }

        if isSelectedFrameReady {
            renderFrameIndex = currentFrameIndex
        }

        evictFrames(outside: residentFrameIndices(around: currentFrameIndex))

        focusedLoadTask?.cancel()
        let sessionID = loadSessionID
        let focusIndices = focusedFrameIndices(around: currentFrameIndex)
        focusedLoadTask = Task { [weak self] in
            guard let self else { return }
            await self.loadFrameBatch(indices: focusIndices, sessionID: sessionID)
            guard !Task.isCancelled, self.loadSessionID == sessionID else { return }
            self.restartBackgroundPreloadIfNeeded()
        }
    }

    private func restartBackgroundPreloadIfNeeded() {
        backgroundPreloadTask?.cancel()
        guard allowsBackgroundPreload(),
              interactionState != .scrubbing,
              !isMapInteracting,
              !frameInfos.isEmpty else { return }

        let sessionID = loadSessionID
        let focused = Set(focusedFrameIndices(around: currentFrameIndex))
        // Preload only the residency window — anything further would be evicted again.
        let resident = residentFrameIndices(around: currentFrameIndex)
        let ordered = prioritizedFrameIndices(count: frameInfos.count, around: currentFrameIndex)
            .filter { resident.contains($0) && !focused.contains($0) }

        backgroundPreloadTask = Task { [weak self] in
            guard let self else { return }
            await self.loadFrameBatch(indices: ordered, sessionID: sessionID)
        }
    }

    private func focusedFrameIndices(around center: Int) -> [Int] {
        Array(prioritizedFrameIndices(count: frameInfos.count, around: center).prefix(5))
    }

    private func loadFocusedFrames(around center: Int, sessionID: UUID) async {
        await loadFrameBatch(indices: focusedFrameIndices(around: center), sessionID: sessionID)
    }

    /// Loads a batch with the NETWORK overlapped (2–3 fetches in flight) while decode
    /// stays strictly serial via `RadarFrameDecodeLane`. History: fully parallel
    /// load+decode was shipped once and reverted — it overheated devices. The moment the
    /// device is warmer than nominal, the window collapses back to sequential.
    private func loadFrameBatch(indices: [Int], sessionID: UUID) async {
        let width = ProcessInfo.processInfo.thermalState == .nominal ? 3 : 1
        var iterator = indices.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            @discardableResult
            func startNext() -> Bool {
                guard !Task.isCancelled, let index = iterator.next() else { return false }
                group.addTask { [weak self] in
                    _ = await self?.loadFrameIfNeeded(at: index, sessionID: sessionID)
                }
                return true
            }
            while inFlight < width, startNext() { inFlight += 1 }
            for await _ in group {
                startNext()
            }
        }
    }

    private func loadFrameIfNeeded(at index: Int, sessionID: UUID) async -> Bool {
        guard loadSessionID == sessionID,
              frameInfos.indices.contains(index),
              frames.indices.contains(index) else {
            return false
        }

        if frames[index] != nil {
            if renderFrameIndex == nil {
                renderFrameIndex = index
            }
            return true
        }

        if loadingFrameIndices.contains(index) {
            return false
        }

        loadingFrameIndices.insert(index)
        defer { loadingFrameIndices.remove(index) }

        let info = frameInfos[index]
        guard let grid = await Self.loadGridIndices(for: info, region: region) else { return false }
        let loadedFrame = OscarRadarFrame(key: info.key, timestamp: info.timestamp,
                                          gridIndices: grid.indices, width: grid.width, height: grid.height)

        guard loadSessionID == sessionID,
              frameInfos.indices.contains(index),
              frames.indices.contains(index) else {
            return false
        }

        frames[index] = loadedFrame
        loadedFrameIndices.insert(index)

        if renderFrameIndex == nil || currentFrameIndex == index {
            renderFrameIndex = index
        }

        if isLoading, hasAnyLoadedFrame {
            isLoading = false
        }

        return true
    }

    private func frame(at index: Int?) -> OscarRadarFrame? {
        guard let index, frames.indices.contains(index) else { return nil }
        return frames[index]
    }

    /// Frame metadata; the transport cache (max-age + ETag) answers repeat calls.
    private static func fetchFrameInfos(region: RadarRegion) async throws -> ([RadarFrameInfo], Components.Schemas.RadarBounds) {
        let response = try await APIClient.shared.radarFrames(region: region.pathComponent)
        // image_bounds (the rendered Mercator rectangle) over the tighter data
        // footprint — see RadarSharedDTOs.
        return (response.frames, response.image_bounds ?? response.bounds)
    }

    /// Download the raw 8-bit value grid and decode it (serial lane) to a compact index
    /// buffer. Colormapping happens on the GPU at draw time (palette LUT in the layer).
    private static func loadGridIndices(for frameInfo: RadarFrameInfo, region: RadarRegion) async -> RadarGridPayload? {
        let fetched: Data?
        do {
            fetched = try await APIClient.shared.radarGrid(
                region: region.pathComponent,
                key: frameInfo.key)
        } catch {
            return nil
        }
        guard let data = fetched else {
            // A dry frame has no grid (404) — that's data ("no precipitation"), not
            // an error. A 1×1 index-0 payload renders fully transparent and marks the
            // tick loaded instead of leaving it on the orange loading state forever.
            return RadarGridPayload(indices: [0], width: 1, height: 1)
        }
        return await RadarFrameDecodeLane.shared.decodeGrid(data)
    }

    /// Minutes between two frame timestamps (nil if either fails to parse). The map
    /// layer uses it to scale a motion field to the actually displayed pair's gap.
    nonisolated static func minutesBetween(_ from: String, _ to: String) -> Int? {
        guard let a = parseFrameDate(from), let b = parseFrameDate(to) else { return nil }
        return Int((b.timeIntervalSince(a) / 60).rounded())
    }

    /// Fetch + decode `/radar/{region}/motion` (best-effort; nil on any failure).
    private static func fetchMotionData(region: RadarRegion) async -> RadarMotionData? {
        guard let payload = try? await APIClient.shared.radarMotion(region: region.pathComponent) else { return nil }
        return RadarMotionData(payload: payload)
    }

    deinit {
        bootstrapTask?.cancel()
        focusedLoadTask?.cancel()
        backgroundPreloadTask?.cancel()
    }
}
