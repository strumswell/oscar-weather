//
//  OscarRadarState.swift
//  Oscar°
//
//  Timeline state for the live radar layer (precipitation or precip-type product):
//  metadata + frame grid loading, playback, scrubbing, and the shared palettes.
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
    /// Active radar product (precipitation radar / categorical precip-type). Use
    /// `setProduct(_:)` to change it — same clearing semantics as `setRegion(_:)`.
    private(set) var product: RadarProduct = .precipitation
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

    @ObservationIgnored nonisolated(unsafe) private var playbackTimer: Timer?
    @ObservationIgnored private var frameInfos: [RadarFrameInfo] = []
    @ObservationIgnored private var frameDates: [Date?] = []
    @ObservationIgnored private var loadSessionID = UUID()
    @ObservationIgnored private var suppressSelectionSideEffects = false
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundPreloadTask: Task<Void, Never>?
    @ObservationIgnored private var focusedLoadTask: Task<Void, Never>?
    @ObservationIgnored private let renderMode: MapRenderMode
    private static let cacheLock = NSLock()
    // Live instances (preview + fullscreen come and go with their views) for the
    // app-level memory-warning purge.
    private static let instances = NSHashTable<OscarRadarState>.weakObjects()

    init(renderMode: MapRenderMode = .fullscreen) {
        self.renderMode = renderMode
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

    var contiguousReadyRange: ClosedRange<Int>? {
        contiguousLoadedRange(
            in: frames.map { $0 != nil },
            around: isSelectedFrameReady ? currentFrameIndex : renderFrameIndex
        )
    }

    var highestContiguouslyReadyForwardIndex: Int? {
        guard isSelectedFrameReady else { return nil }

        var index = currentFrameIndex
        while index + 1 < frames.count, frames[index + 1] != nil {
            index += 1
        }
        return index
    }

    var furthestContiguouslyReadyTimestamp: String? {
        guard let index = highestContiguouslyReadyForwardIndex,
              frameTimestamps.indices.contains(index) else { return nil }
        return frameTimestamps[index]
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

    // MARK: - Shared Cache

    // Keyed by region + product: frame keys are bare timestamps that collide
    // across sources, so caches must be source-qualified.
    private struct SourceKey: Hashable {
        let region: RadarRegion
        let product: RadarProduct
    }

    private var sourceKey: SourceKey { SourceKey(region: region, product: product) }

    private static var cachedFrameInfos: [SourceKey: [RadarFrameInfo]] = [:]
    private static var cachedBounds: [SourceKey: Components.Schemas.RadarBounds] = [:]
    private static var lastFetchedTime: [SourceKey: Date] = [:]
    private static let cacheDuration: TimeInterval = 10 * 60

    private static func isCacheValid(for source: SourceKey) -> Bool {
        guard let last = lastFetchedTime[source] else { return false }
        return Date().timeIntervalSince(last) < cacheDuration
    }

    // MARK: - Region / product

    /// Switches radar coverage. Clears the loaded frames + in-flight work so the
    /// next `loadCurrentFrame()`/`loadAllFrames()` fetches the new region. No-op
    /// if the region is unchanged.
    func setRegion(_ newRegion: RadarRegion) {
        guard newRegion != region else { return }
        region = newRegion
        resetForSourceChange()
    }

    /// Switches between the precipitation radar and the categorical precip-type
    /// product. Same clearing semantics as `setRegion(_:)`.
    func setProduct(_ newProduct: RadarProduct) {
        guard newProduct != product else { return }
        product = newProduct
        resetForSourceChange()
    }

    private func resetForSourceChange() {
        bootstrapTask?.cancel()
        focusedLoadTask?.cancel()
        backgroundPreloadTask?.cancel()
        pause()

        loadSessionID = UUID()
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

    /// Reloads for the active region, picking the load depth that matches the
    /// configured render mode (preview = current frame only, fullscreen = all).
    func reloadForCurrentRegion() async {
        switch renderMode {
        case .preview:
            await loadCurrentFrame()
        case .fullscreen:
            await loadAllFrames()
        }
    }

    /// Reload only when the shared metadata cache has expired (or nothing ever
    /// loaded, e.g. the last attempt failed offline) — the foreground/periodic
    /// refresh hook. A quick app switch stays a no-op; a return after the cache
    /// window re-fetches the frame list so the map doesn't keep replaying stale
    /// frames as "live".
    func refreshIfStale() async {
        guard !isLoading else { return }
        guard !Self.isCacheValid(for: sourceKey) || !hasAnyLoadedFrame else { return }
        await reloadForCurrentRegion()
    }

    // MARK: - Loading

    /// Loads only the frame closest to the current time.
    /// Designed for NowView: fast, minimal network work.
    func loadCurrentFrame() async {
        await loadFrames(allowBackgroundPreload: false)
    }

    /// Loads all frames, showing the scrubber skeleton immediately after metadata
    /// arrives and filling in ticks progressively as each image downloads.
    func loadAllFrames() async {
        await loadFrames(allowBackgroundPreload: allowsBackgroundPreload(for: renderMode))
    }

    // MARK: - Playback

    func play() {
        guard hasAnyLoadedFrame else { return }
        playbackTimer?.invalidate()
        isPlaying = true
        interactionState = .playing
        restartBackgroundPreloadIfNeeded()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceFrame()
            }
        }
    }

    func pause() {
        isPlaying = false
        interactionState = .idle
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    /// Stops the internal Timer without changing `isPlaying`.
    /// Called when the Metal display link takes over frame advancement.
    func cancelInternalTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
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
                let (allFrameInfos, boundsInfo) = try await Self.fetchFrameInfos(source: self.sourceKey)
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

                // Motion fields load in parallel and are optional — the layer renders a
                // plain cross-fade until they arrive. The typed product morphs too:
                // the warp moves sampling POSITIONS, and the layer blends typed frames
                // in color space (categorical indices are never interpolated).
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
                self.error = "Fehler beim Laden: \(error.localizedDescription)"
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
        guard allowsBackgroundPreload(for: renderMode),
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
        Array(prioritizedFrameIndices(count: frameInfos.count, around: center).prefix(renderMode.focusedPreloadCount))
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
        await Self.warmPalette(id: product.colormapId)
        guard let grid = await Self.loadGridIndices(for: info, source: sourceKey) else { return false }
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

    /// Fetches frame metadata from the server, or returns the cached list if still valid.
    /// Clears the image cache when the metadata expires, since frame keys will have changed.
    private static func fetchFrameInfos(source: SourceKey) async throws -> ([RadarFrameInfo], Components.Schemas.RadarBounds) {
        if let cached = cacheLock.withLock({ () -> ([RadarFrameInfo], Components.Schemas.RadarBounds)? in
            if isCacheValid(for: source),
               let bounds = cachedBounds[source],
               let infos = cachedFrameInfos[source], !infos.isEmpty {
                return (infos, bounds)
            }
            return nil
        }) {
            return cached
        }

        let response = try await APIClient.shared.radarFrames(region: source.region.pathComponent)
        // image_bounds (the rendered Mercator rectangle) over the tighter data
        // footprint — see RadarSharedDTOs.
        let overlayBounds = response.image_bounds ?? response.bounds
        cacheLock.withLock {
            cachedFrameInfos[source] = response.frames
            cachedBounds[source] = overlayBounds
            lastFetchedTime[source] = Date()
        }
        return (response.frames, overlayBounds)
    }

    /// Download the raw 8-bit value grid and decode it (serial lane) to a compact index
    /// buffer. Colormapping happens on the GPU at draw time (palette LUT in the layer).
    private static func loadGridIndices(for frameInfo: RadarFrameInfo, source: SourceKey) async -> RadarGridPayload? {
        let fetched: Data?
        do {
            fetched = try await APIClient.shared.radarGrid(
                region: source.region.pathComponent,
                key: frameInfo.key,
                typed: source.product == .precipitationTyped)
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

    // MARK: - Value-grid colormap (client-side rendering path)

    // Resolved once per palette id (server-preferred, local fallback); every grid
    // frame colormaps against its product's entry.
    private static var cachedPalettes: [String: [PixelRGBA]] = [:]

    /// The resolved 256-entry palette for a colormap id (warming it on first call). Used by
    /// the off-main GPU materialization path; resolution is cheap (one cached network fetch,
    /// then memory).
    static func resolvedPalette(id: String) async -> [PixelRGBA] {
        await warmPalette(id: id)
        return cachedPalettes[id] ?? fallbackPalette(id: id)
    }

    /// Resolves a 256-entry palette: server `/colormaps/{id}` preferred, local fallback
    /// (kept in sync with the server) if it's unavailable.
    private static func warmPalette(id: String) async {
        if cachedPalettes[id] != nil { return }
        if let data = try? await APIClient.shared.colormap(id: id), data.count == 256 * 4 {
            cachedPalettes[id] = (0..<256).map {
                let o = $0 * 4
                return PixelRGBA(r: data[o], g: data[o + 1], b: data[o + 2], a: data[o + 3])
            }
            return
        }
        if cachedPalettes[id] == nil { cachedPalettes[id] = fallbackPalette(id: id) }
    }

    private static func fallbackPalette(id: String) -> [PixelRGBA] {
        id == RadarProduct.precipitationTyped.colormapId
            ? TypedRadarPalette.buildPalette()
            : RadarPlasma.buildPalette()
    }

    deinit {
        bootstrapTask?.cancel()
        focusedLoadTask?.cancel()
        backgroundPreloadTask?.cancel()
        playbackTimer?.invalidate()
    }
}
