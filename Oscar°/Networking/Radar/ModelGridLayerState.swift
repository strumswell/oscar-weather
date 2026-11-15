//
//  ModelGridLayerState.swift
//  Oscar°
//
//  Timeline state for the ICON-D2 / ECMWF value-grid layers (world images,
//  palettes, progressive frame loading).
//

import Foundation
import Observation

// MARK: - Model Full-World Image Layer State

@MainActor
@Observable
final class ModelGridLayerState {

    private(set) var frames: [RadarGridPayload?] = []
    private(set) var frameTimestamps: [String] = []
    private(set) var frameKeys: [String] = []
    private(set) var bounds: OscarRadarBounds?
    private(set) var motion: RadarMotionData?
    var currentFrameIndex: Int = 0 {
        didSet {
            guard currentFrameIndex != oldValue else { return }
            handleFrameSelectionChanged()
        }
    }
    var isLoading: Bool = false
    var isPlaying: Bool = false
    var error: String?
    private(set) var currentLayer: WeatherTileLayer?
    private(set) var startsAfter: Date?
    private(set) var loadingFrameIndices: Set<Int> = []
    private(set) var loadedFrameIndices: Set<Int> = []
    private(set) var renderFrameIndex: Int?
    private(set) var isMapInteracting = false
    @ObservationIgnored var preloadsWide = true

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var failedFrameIndices: Set<Int> = []
    @ObservationIgnored private var loadsHeld = false
    @ObservationIgnored private let playback = PlaybackTicker()
    @ObservationIgnored private var frameInfos: [ModelFrameInfo] = []
    @ObservationIgnored private var frameDates: [Date?] = []
    @ObservationIgnored private var loadSessionID = UUID()
    @ObservationIgnored private var suppressSelectionSideEffects = false
    @ObservationIgnored private var lastMetadataLoad: Date?
    private static let metadataStaleAfter: TimeInterval = 10 * 60

    private static let gridResidencyBudget = adaptiveCacheBudget(
        fraction: 0.16, floor: 64 * 1024 * 1024, cap: 512 * 1024 * 1024)

    private static let gridCache: NSCache<NSString, GridPayloadBox> = {
        let cache = NSCache<NSString, GridPayloadBox>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    private static let instances = NSHashTable<ModelGridLayerState>.weakObjects()

    static func purgeDecodedCaches() {
        gridCache.removeAllObjects()
        for state in instances.allObjects {
            state.loadsHeld = true
            let anchor = state.renderFrameIndex ?? state.currentFrameIndex
            var keep: Set<Int> = [anchor]
            if let next = nextLoadedIndex(in: state.frames.map { $0 != nil }, after: anchor) {
                keep.insert(next)
            }
            for index in state.frames.indices
            where state.frames[index] != nil && !keep.contains(index) {
                state.frames[index] = nil
                state.loadedFrameIndices.remove(index)
            }
        }
    }

    init() {
        Self.instances.add(self)
    }

    // MARK: - Derived

    var currentFrame: RadarGridPayload? {
        frame(at: renderFrameIndex ?? currentFrameIndex)
    }

    var nextFrameKeyed: (key: String, payload: RadarGridPayload)? {
        guard let anchor = renderFrameIndex ?? (isSelectedFrameReady ? currentFrameIndex : nil) else { return nil }
        let loaded = frames.map { $0 != nil }
        guard let nextIndex = nextLoadedIndex(in: loaded, after: anchor),
              frameKeys.indices.contains(nextIndex),
              let payload = frame(at: nextIndex) else { return nil }
        return (frameKeys[nextIndex], payload)
    }

    var currentFrameTimestamp: String? {
        guard !frameTimestamps.isEmpty, frameTimestamps.indices.contains(currentFrameIndex) else { return nil }
        return frameTimestamps[currentFrameIndex]
    }

    var currentFrameKey: String? {
        guard !frameKeys.isEmpty,
              let index = renderFrameIndex ?? (isSelectedFrameReady ? currentFrameIndex : nil),
              frameKeys.indices.contains(index) else { return nil }
        return frameKeys[index]
    }

    func timestamp(forKey key: String) -> String? {
        guard let index = frameKeys.firstIndex(of: key),
              frameTimestamps.indices.contains(index) else { return nil }
        return frameTimestamps[index]
    }

    var hasAnyLoadedFrame: Bool {
        frames.contains { $0 != nil }
    }

    var isSelectedFrameReady: Bool {
        frames.indices.contains(currentFrameIndex) && frames[currentFrameIndex] != nil
    }

    // MARK: - Playback

    func play() {
        guard !frames.isEmpty else { return }
        isPlaying = true
        loadsHeld = false
        pumpLoads()
        playback.start(interval: .milliseconds(800)) { [weak self] in self?.advanceFrame() }
    }

    func pause() {
        isPlaying = false
        playback.stop()
    }

    func advanceFrame() {
        guard isPlaying, !frames.isEmpty else { return }
        let loaded = frames.map { $0 != nil }
        guard let nextIndex = nextLoadedIndex(in: loaded, after: currentFrameIndex) else {
            return
        }
        currentFrameIndex = nextIndex
    }

    func cancelInternalTimer() {
        playback.stop()
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

    // MARK: - Load

    func loadLayer(_ layer: WeatherTileLayer, after cutoff: Date? = nil) async {
        loadTask?.cancel()
        cancelFrameLoads()

        let sessionID = UUID()
        loadSessionID = sessionID

        currentLayer = layer
        startsAfter = cutoff
        isLoading = true
        error = nil
        frames = []
        frameTimestamps = []
        frameDates = []
        frameKeys = []
        frameInfos = []
        bounds = OscarRadarBounds(north: 85.051, south: -85.051, west: -180, east: 180)
        motion = nil
        loadedFrameIndices.removeAll()
        renderFrameIndex = nil

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let decoded = try await APIClient.shared.modelFrames(model: layer.windFieldPrefix)
                guard !Task.isCancelled, self.loadSessionID == sessionID else { return }

                let fetchedFrameInfos = decoded.frames.filter { info in
                    guard let cutoff else { return true }
                    return parseFrameDate(info.validTime).map { $0 > cutoff } ?? false
                }
                let fetchedBounds = decoded.image_bounds?.asDomain ?? decoded.bounds?.asDomain
                    ?? OscarRadarBounds(north: 85.051, south: -85.051, west: -180, east: 180)

                let timestamps = fetchedFrameInfos.map(\.validTime)
                let dates = timestamps.map(parseFrameDate)
                let keys = fetchedFrameInfos.map(\.key)
                let closest = closestTimestampIndex(in: dates)

                self.suppressSelectionSideEffects = true
                self.frameInfos = fetchedFrameInfos
                self.frames = Array(repeating: nil, count: fetchedFrameInfos.count)
                self.loadedFrameIndices = []
                self.frameTimestamps = timestamps
                self.frameDates = dates
                self.frameKeys = keys
                self.bounds = fetchedBounds
                self.currentFrameIndex = closest
                self.suppressSelectionSideEffects = false
                self.lastMetadataLoad = Date()

                if layer.morphsAlongMotion {
                    let model = layer.windFieldPrefix
                    Task { [weak self] in
                        let data = await Self.fetchMotionData(model: model)
                        guard let self, self.loadSessionID == sessionID else { return }
                        self.motion = data
                    }
                }

                self.loadsHeld = false
                self.pumpLoads()
                if self.loadingFrameIndices.isEmpty { self.isLoading = false }
            } catch {
                guard self.loadSessionID == sessionID else { return }
                self.isLoading = false
                self.error = String(localized: "Fehler beim Laden: \(error.localizedDescription)")
            }
        }

        await loadTask?.value
    }

    func refreshIfStale() async {
        guard let layer = currentLayer, !isLoading else { return }
        if hasAnyLoadedFrame, let lastMetadataLoad,
           Date().timeIntervalSince(lastMetadataLoad) < Self.metadataStaleAfter {
            return
        }
        await loadLayer(layer, after: startsAfter)
    }

    // MARK: - Helpers

    private static func fetchMotionData(model: String) async -> RadarMotionData? {
        guard let payload = try? await APIClient.shared.modelMotion(model: model) else { return nil }
        return RadarMotionData(payload: payload)
    }

    private func handleFrameSelectionChanged() {
        guard !suppressSelectionSideEffects else { return }
        guard !frameInfos.isEmpty,
              currentLayer != nil,
              frameInfos.indices.contains(currentFrameIndex) else { return }

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

    private func residentFrameIndices(around center: Int) -> Set<Int> {
        let bytesPerFrame = frames.lazy.compactMap { $0 }.map { $0.width * $0.height }.max() ?? 4_000_000
        var resident = residencyWindow(count: frames.count, center: center,
                                       bytesPerFrame: bytesPerFrame, budget: Self.gridResidencyBudget)
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

    private func pumpLoads() {
        guard !loadsHeld, currentLayer != nil, !frameInfos.isEmpty else { return }
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
        guard let layer = currentLayer else { return }
        let sessionID = loadSessionID
        let key = frameInfos[index].key
        let cacheKey = "\(layer.rawValue)/\(key)"
        let model = layer.windFieldPrefix, variable = layer.variableSegment
        loadingFrameIndices.insert(index)
        loadTasks[index] = Task { [weak self] in
            let payload: RadarGridPayload?
            if let cached = Self.gridCache.object(forKey: cacheKey as NSString) {
                payload = cached.payload
            } else {
                payload = await Self.fetchGrid(model: model, key: key, variable: variable)
                if let payload {
                    Self.gridCache.setObject(GridPayloadBox(payload: payload), forKey: cacheKey as NSString,
                                             cost: payload.width * payload.height)
                }
            }
            self?.finishLoad(at: index, key: key, payload: payload, sessionID: sessionID)
        }
    }

    private static func fetchGrid(model: String, key: String, variable: String) async -> RadarGridPayload? {
        let fetched: Data?
        do {
            fetched = try await APIClient.shared.modelGrid(model: model, key: key, variable: variable)
        } catch {
            return nil
        }
        guard let data = fetched else { return RadarGridPayload(indices: [0], width: 1, height: 1) }
        return await RadarFrameDecodeLane.shared.decodeGrid(data)
    }

    private func finishLoad(at index: Int, key: String, payload: RadarGridPayload?, sessionID: UUID) {
        guard loadSessionID == sessionID else { return }
        loadingFrameIndices.remove(index)
        loadTasks[index] = nil

        if let payload {
            if frameInfos.indices.contains(index), frameInfos[index].key == key, frames.indices.contains(index),
               residentFrameIndices(around: currentFrameIndex).contains(index) {
                frames[index] = payload
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
    }

    private func cancelFrameLoads() {
        loadTasks.values.forEach { $0.cancel() }
        loadTasks.removeAll()
        loadingFrameIndices.removeAll()
        failedFrameIndices.removeAll()
        loadsHeld = false
    }

    private func frame(at index: Int?) -> RadarGridPayload? {
        guard let index, frames.indices.contains(index) else { return nil }
        return frames[index]
    }

    deinit {
        loadTask?.cancel()
        loadTasks.values.forEach { $0.cancel() }
    }
}

// MARK: - Motion morphing (per model)

extension WeatherTileLayer {
    var morphsAlongMotion: Bool {
        self == .iconPrecip || self == .ecmwfPrecip
    }
}
