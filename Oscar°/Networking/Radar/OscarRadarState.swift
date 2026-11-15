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
    var frames: [OscarRadarFrame?] = []

    private(set) var frameTimestamps: [String] = []

    var bounds: OscarRadarBounds?
    private(set) var motion: RadarMotionData?
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
    private(set) var loadedFrameIndices: Set<Int> = []
    private(set) var renderFrameIndex: Int?
    private(set) var isMapInteracting = false
    @ObservationIgnored var preloadsWide = true

    @ObservationIgnored private let playback = PlaybackTicker()
    @ObservationIgnored private var frameInfos: [RadarFrameInfo] = []
    @ObservationIgnored private var frameDates: [Date?] = []
    @ObservationIgnored private var loadSessionID = UUID()
    @ObservationIgnored private var suppressSelectionSideEffects = false
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var loadTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var failedFrameIndices: Set<Int> = []
    @ObservationIgnored private var loadsHeld = false
    @ObservationIgnored private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var lastMetadataLoad: Date?
    private static let metadataStaleAfter: TimeInterval = 10 * 60
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

    var currentFrameTimestamp: String? {
        guard currentFrameIndex < frameTimestamps.count else { return nil }
        return frameTimestamps[currentFrameIndex]
    }

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

    private static let gridResidencyBudget = adaptiveCacheBudget(
        fraction: 0.16, floor: 64 * 1024 * 1024, cap: 512 * 1024 * 1024)

    private func residentFrameIndices(around center: Int) -> Set<Int> {
        let bytesPerFrame = frames.lazy.compactMap { $0 }
            .map { $0.gridPayload.width * $0.gridPayload.height }
            .max() ?? 4_000_000
        var resident = residencyWindow(count: frames.count, center: center,
                                       bytesPerFrame: bytesPerFrame, budget: Self.gridResidencyBudget)
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

    static func purgeDecodedGrids() {
        for state in instances.allObjects {
            state.loadsHeld = true
            let anchor = state.renderFrameIndex ?? state.currentFrameIndex
            var keep: Set<Int> = [anchor]
            if let next = nextLoadedIndex(in: state.frames.map { $0 != nil }, after: anchor) {
                keep.insert(next)
            }
            state.evictFrames(outside: keep)
        }
    }

    // MARK: - Region

    func setRegion(_ newRegion: RadarRegion) {
        guard newRegion != region else { return }
        region = newRegion
        resetForSourceChange()
    }

    private func resetForSourceChange() {
        bootstrapTask?.cancel()
        cancelFrameLoads()
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
        loadedFrameIndices.removeAll()
        renderFrameIndex = nil
        currentFrameIndex = 0
        suppressSelectionSideEffects = false
    }

    func reloadForCurrentRegion() async {
        await loadAllFrames()
    }

    func refreshIfStale() async {
        guard !isLoading else { return }
        if hasAnyLoadedFrame, let lastMetadataLoad,
           Date().timeIntervalSince(lastMetadataLoad) < Self.metadataStaleAfter {
            return
        }
        await reloadForCurrentRegion()
    }

    // MARK: - Staged frames

    func showStagedFrames(_ staged: [OscarRadarFrame], dates: [Date], bounds: OscarRadarBounds, motion: RadarMotionData?) {
        resetForSourceChange()
        suppressSelectionSideEffects = true
        self.bounds = bounds
        self.motion = motion
        frameTimestamps = staged.map(\.timestamp)
        frameDates = dates
        frames = staged
        loadedFrameIndices = Set(staged.indices)
        currentFrameIndex = closestTimestampIndex(in: dates)
        suppressSelectionSideEffects = false
        lastMetadataLoad = Date()
    }

    // MARK: - Loading

    func loadAllFrames() async {
        await loadFrames()
    }

    func waitForFrames() async {
        await bootstrapTask?.value
        while !loadingFrameIndices.isEmpty { await nextLoadCompletion() }
    }

    // MARK: - Playback

    func play() {
        guard hasAnyLoadedFrame else { return }
        isPlaying = true
        loadsHeld = false
        pumpLoads()
        playback.start(interval: .milliseconds(500)) { [weak self] in self?.advanceFrame() }
    }

    func pause() {
        isPlaying = false
        playback.stop()
    }

    func cancelInternalTimer() {
        playback.stop()
    }

    func advanceFrame() {
        guard isPlaying, !frames.isEmpty else { return }
        let loaded = frames.map { $0 != nil }
        guard let next = nextLoadedIndex(in: loaded, after: currentFrameIndex) else {
            return
        }
        currentFrameIndex = next
    }

    func beginScrubbing() {
        pause()
    }

    func endScrubbing() {}

    func beginMapInteraction() {
        guard !isMapInteracting else { return }
        isMapInteracting = true
    }

    func endMapInteraction() {
        guard isMapInteracting else { return }
        isMapInteracting = false
        pumpLoads()
    }

    // MARK: - Private Helpers

    private func loadFrames() async {
        bootstrapTask?.cancel()
        cancelFrameLoads()

        let sessionID = UUID()
        loadSessionID = sessionID
        isLoading = true
        error = nil
        renderFrameIndex = nil

        bootstrapTask = Task { [weak self] in
            guard let self else { return }

            do {
                let (allFrameInfos, boundsInfo) = try await Self.fetchFrameInfos(region: self.region)
                guard !Task.isCancelled, self.loadSessionID == sessionID else { return }
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

                let motionRegion = self.region
                Task { [weak self] in
                    let data = await Self.fetchMotionData(region: motionRegion)
                    guard let self, self.loadSessionID == sessionID else { return }
                    self.motion = data
                }

                self.loadsHeld = false
                self.pumpLoads()
                while !self.hasAnyLoadedFrame, !self.loadingFrameIndices.isEmpty, self.loadSessionID == sessionID {
                    await self.nextLoadCompletion()
                }
                guard self.loadSessionID == sessionID else { return }
                self.isLoading = false
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

        evictFrames(outside: residentFrameIndices(around: currentFrameIndex))
        showNearestLoadedFrame()
        if !isPlaying { failedFrameIndices.removeAll() }
        loadsHeld = false
        pumpLoads()
    }

    private func showNearestLoadedFrame() {
        guard let nearest = nearestLoadedIndex(in: frames.map { $0 != nil }, around: currentFrameIndex),
              nearest != renderFrameIndex else { return }
        if let renderFrameIndex, abs(renderFrameIndex - currentFrameIndex) <= abs(nearest - currentFrameIndex) { return }
        renderFrameIndex = nearest
    }

    private func pumpLoads() {
        guard !loadsHeld, !frameInfos.isEmpty else { return }
        let wide = preloadsWide && allowsBackgroundPreload() && !isMapInteracting
        let focus = Set(prioritizedFrameIndices(count: frames.count, around: currentFrameIndex).prefix(5))
        let resident = residentFrameIndices(around: currentFrameIndex)
        let picks = loadsToStart(count: frames.count, center: currentFrameIndex,
                                 inFlight: loadingFrameIndices.count, limit: frameLoadLimit()) { index in
            frames[index] == nil && !loadingFrameIndices.contains(index) && !failedFrameIndices.contains(index)
                && resident.contains(index) && (wide || focus.contains(index))
        }
        for index in picks { startLoad(at: index) }
    }

    private func startLoad(at index: Int) {
        let sessionID = loadSessionID
        let info = frameInfos[index]
        let region = self.region
        loadingFrameIndices.insert(index)
        loadTasks[index] = Task { [weak self] in
            let grid = await Self.loadGridIndices(for: info, region: region)
            self?.finishLoad(at: index, info: info, grid: grid, sessionID: sessionID)
        }
    }

    private func finishLoad(at index: Int, info: RadarFrameInfo, grid: RadarGridPayload?, sessionID: UUID) {
        guard loadSessionID == sessionID else { return }
        loadingFrameIndices.remove(index)
        loadTasks[index] = nil

        if let grid {
            if frameInfos.indices.contains(index), frameInfos[index].key == info.key, frames.indices.contains(index),
               residentFrameIndices(around: currentFrameIndex).contains(index) {
                frames[index] = OscarRadarFrame(key: info.key, timestamp: info.timestamp,
                                                gridIndices: grid.indices, width: grid.width, height: grid.height)
                loadedFrameIndices.insert(index)
                showNearestLoadedFrame()
            }
        } else {
            failedFrameIndices.insert(index)
        }

        pumpLoads()
        if isLoading, hasAnyLoadedFrame || loadingFrameIndices.isEmpty {
            isLoading = false
        }
        resumeLoadWaiters()
    }

    private func cancelFrameLoads() {
        loadTasks.values.forEach { $0.cancel() }
        loadTasks.removeAll()
        loadingFrameIndices.removeAll()
        failedFrameIndices.removeAll()
        loadsHeld = false
        resumeLoadWaiters()
    }

    private func nextLoadCompletion() async {
        await withCheckedContinuation { loadWaiters.append($0) }
    }

    private func resumeLoadWaiters() {
        let waiters = loadWaiters
        loadWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func frame(at index: Int?) -> OscarRadarFrame? {
        guard let index, frames.indices.contains(index) else { return nil }
        return frames[index]
    }

    private static func fetchFrameInfos(region: RadarRegion) async throws -> ([RadarFrameInfo], Components.Schemas.RadarBounds) {
        let response = try await APIClient.shared.radarFrames(region: region.pathComponent)
        return (response.frames, response.image_bounds ?? response.bounds)
    }

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
            return RadarGridPayload(indices: [0], width: 1, height: 1)
        }
        return await RadarFrameDecodeLane.shared.decodeRawGrid(data)
    }

    nonisolated static func minutesBetween(_ from: String, _ to: String) -> Int? {
        guard let a = parseFrameDate(from), let b = parseFrameDate(to) else { return nil }
        return Int((b.timeIntervalSince(a) / 60).rounded())
    }

    private static func fetchMotionData(region: RadarRegion) async -> RadarMotionData? {
        guard let payload = try? await APIClient.shared.radarMotion(region: region.pathComponent) else { return nil }
        return RadarMotionData(payload: payload)
    }

    deinit {
        bootstrapTask?.cancel()
        loadTasks.values.forEach { $0.cancel() }
    }
}
