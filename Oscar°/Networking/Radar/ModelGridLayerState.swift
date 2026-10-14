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
    private(set) var interactionState: MapInteractionState = .idle
    private(set) var isMapInteracting = false

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundPreloadTask: Task<Void, Never>?
    @ObservationIgnored private var focusedLoadTask: Task<Void, Never>?
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
            state.backgroundPreloadTask?.cancel()
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

    var nextFrame: RadarGridPayload? {
        nextFrameKeyed?.payload
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
        interactionState = .playing
        restartBackgroundPreloadIfNeeded()
        playback.start(interval: .milliseconds(800)) { [weak self] in self?.advanceFrame() }
    }

    func pause() {
        isPlaying = false
        interactionState = .idle
        playback.stop()
    }

    func advanceFrame() {
        guard !frames.isEmpty else { return }
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

    // MARK: - Load

    func loadLayer(_ layer: WeatherTileLayer, after cutoff: Date? = nil) async {
        loadTask?.cancel()
        focusedLoadTask?.cancel()
        backgroundPreloadTask?.cancel()

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
        loadingFrameIndices.removeAll()
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

                await self.loadFrameBatch(
                    indices: self.focusedFrameIndices(around: closest),
                    sessionID: sessionID,
                    layer: layer
                )

                guard !Task.isCancelled, self.loadSessionID == sessionID else { return }
                self.isLoading = false
                self.restartBackgroundPreloadIfNeeded()
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

        if isSelectedFrameReady {
            renderFrameIndex = currentFrameIndex
        }

        evictFrames(outside: residentFrameIndices(around: currentFrameIndex))

        focusedLoadTask?.cancel()
        guard let layer = currentLayer else { return }
        let sessionID = loadSessionID
        let focusIndices = focusedFrameIndices(around: currentFrameIndex)

        focusedLoadTask = Task { [weak self] in
            guard let self else { return }
            await self.loadFrameBatch(
                indices: focusIndices,
                sessionID: sessionID,
                layer: layer
            )
            guard !Task.isCancelled, self.loadSessionID == sessionID else { return }
            self.restartBackgroundPreloadIfNeeded()
        }
    }

    private func restartBackgroundPreloadIfNeeded() {
        backgroundPreloadTask?.cancel()
        guard allowsBackgroundPreload(),
              interactionState != .scrubbing,
              !isMapInteracting,
              let layer = currentLayer,
              !frameInfos.isEmpty else { return }

        let sessionID = loadSessionID
        let focused = Set(focusedFrameIndices(around: currentFrameIndex))
        let resident = residentFrameIndices(around: currentFrameIndex)
        let ordered = prioritizedFrameIndices(count: frameInfos.count, around: currentFrameIndex)
            .filter { resident.contains($0) && !focused.contains($0) }

        backgroundPreloadTask = Task { [weak self] in
            guard let self else { return }
            await self.loadFrameBatch(
                indices: ordered,
                sessionID: sessionID,
                layer: layer
            )
        }
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

    private func focusedFrameIndices(around center: Int) -> [Int] {
        Array(prioritizedFrameIndices(count: frameInfos.count, around: center).prefix(5))
    }

    private func loadFrameBatch(
        indices: [Int],
        sessionID: UUID,
        layer: WeatherTileLayer
    ) async {
        for index in indices {
            guard !Task.isCancelled else { return }
            _ = await loadFrameIfNeeded(
                at: index,
                sessionID: sessionID,
                layer: layer
            )
        }
    }

    private func loadFrameIfNeeded(
        at index: Int,
        sessionID: UUID,
        layer: WeatherTileLayer
    ) async -> Bool {
        guard loadSessionID == sessionID,
              currentLayer == layer,
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
        let cacheKey = "\(layer.rawValue)/\(info.key)"

        let payload: RadarGridPayload?
        if let cached = Self.gridCache.object(forKey: cacheKey as NSString) {
            payload = cached.payload
        } else {
            guard !Task.isCancelled else { return false }
            let fetched: Data?
            do {
                fetched = try await APIClient.shared.modelGrid(
                    model: layer.windFieldPrefix, key: info.key, variable: layer.variableSegment)
            } catch {
                return false
            }
            let decoded: RadarGridPayload?
            if let data = fetched {
                decoded = await RadarFrameDecodeLane.shared.decodeGrid(data)
            } else {
                decoded = RadarGridPayload(indices: [0], width: 1, height: 1)
            }
            guard let decoded else { return false }
            Self.gridCache.setObject(
                GridPayloadBox(payload: decoded),
                forKey: cacheKey as NSString,
                cost: decoded.width * decoded.height
            )
            payload = decoded
        }

        guard let payload,
              loadSessionID == sessionID,
              currentLayer == layer,
              frames.indices.contains(index) else {
            return false
        }

        frames[index] = payload
        loadedFrameIndices.insert(index)

        if renderFrameIndex == nil || currentFrameIndex == index {
            renderFrameIndex = index
        }

        if isLoading, hasAnyLoadedFrame {
            isLoading = false
        }

        return true
    }

    private func frame(at index: Int?) -> RadarGridPayload? {
        guard let index, frames.indices.contains(index) else { return nil }
        return frames[index]
    }

    deinit {
        loadTask?.cancel()
        backgroundPreloadTask?.cancel()
        focusedLoadTask?.cancel()
    }
}

// MARK: - Motion morphing (per model)

extension WeatherTileLayer {
    var morphsAlongMotion: Bool {
        self == .iconPrecip || self == .ecmwfPrecip
    }
}
