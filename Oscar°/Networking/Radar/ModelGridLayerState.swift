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

    // Pre-sized when metadata arrives; slots fill in as grids download. Frames are
    // the server's 8-bit value grids; the map layer colormaps them on the GPU with
    // the variable's /colormaps palette (see WeatherTileLayer.colormapId).
    private(set) var frames: [RadarGridPayload?] = []
    private(set) var frameTimestamps: [String] = []
    private(set) var frameKeys: [String] = []
    private(set) var bounds: OscarRadarBounds?
    /// Per-pair motion fields for the precip morph (`/models/{model}/motion`),
    /// fetched alongside the frame list. Byte-identical wire shape to the radar
    /// payload, so the radar decoder parses it. nil for temperature/wind layers.
    private(set) var motion: RadarMotionData?
    /// Selected frame index from the timeline. Rendering may temporarily stay on
    /// the last ready frame if the selected frame is still warming.
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
    private(set) var loadingFrameIndices: Set<Int> = []
    // Stored (not derived from `frames`) — it's read in the per-frame-load hot path
    // and rebuilding a Set per read made every load O(frame count).
    private(set) var loadedFrameIndices: Set<Int> = []
    private(set) var renderFrameIndex: Int?
    private(set) var interactionState: MapInteractionState = .idle
    private(set) var isMapInteracting = false

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundPreloadTask: Task<Void, Never>?
    @ObservationIgnored private var focusedLoadTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var playbackTimer: Timer?
    @ObservationIgnored private var frameInfos: [ModelFrameInfo] = []
    @ObservationIgnored private var frameDates: [Date?] = []
    @ObservationIgnored private var loadSessionID = UUID()
    @ObservationIgnored private var suppressSelectionSideEffects = false
    @ObservationIgnored private var lastMetadataLoad: Date?
    @ObservationIgnored private let renderMode: MapRenderMode
    /// How long loaded metadata counts as fresh for `refreshIfStale` — a full
    /// reload re-decodes every grid, so this is deliberately coarser than the
    /// server's 60 s frames max-age. Mirrors the radar metadata cache window.
    private static let metadataStaleAfter: TimeInterval = 10 * 60

    // Shared across instances — survives layer switches. Grids are 1 byte/px, so the
    // budget is ~4× the frame count the old RGBA cache could hold.
    private static let gridCache: NSCache<NSString, GridPayloadBox> = {
        let cache = NSCache<NSString, GridPayloadBox>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    // Live instances (preview + fullscreen come and go with their views) for the
    // app-level memory-warning purge.
    private static let instances = NSHashTable<ModelGridLayerState>.weakObjects()

    /// App-level memory-warning hook: clears the shared grid cache and drops every
    /// instance's decoded grids except the displayed pair. Evicted frames reload on
    /// demand, exactly like not-yet-loaded ones.
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

    /// Per-variable palettes from `/colormaps/{id}` (256 RGBA entries), cached for the
    /// process. nil until fetched; the layer renders once it resolves.
    @ObservationIgnored private static var cachedPalettes: [String: [PixelRGBA]] = [:]

    static func palette(for colormapId: String) async -> [PixelRGBA]? {
        if let cached = cachedPalettes[colormapId] { return cached }
        guard let data = try? await APIClient.shared.colormap(id: colormapId),
              data.count == 256 * 4 else { return nil }
        let palette = (0..<256).map {
            let o = $0 * 4
            return PixelRGBA(r: data[o], g: data[o + 1], b: data[o + 2], a: data[o + 3])
        }
        cachedPalettes[colormapId] = palette
        return palette
    }

    init(renderMode: MapRenderMode = .fullscreen) {
        self.renderMode = renderMode
        Self.instances.add(self)
    }

    // MARK: - Derived

    var currentFrame: RadarGridPayload? {
        frame(at: renderFrameIndex ?? currentFrameIndex)
    }

    var nextFrame: RadarGridPayload? {
        nextFrameKeyed?.payload
    }

    /// The frame after the rendered one plus its key — the cross-fade target for the
    /// map layer (keys the layer's texture cache, like the radar path).
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

    /// Timestamp for a frame key — the map layer rescales a motion field by the
    /// actually displayed pair's timestamp gap (progressive loading can skip frames).
    func timestamp(forKey key: String) -> String? {
        guard let index = frameKeys.firstIndex(of: key),
              frameTimestamps.indices.contains(index) else { return nil }
        return frameTimestamps[index]
    }

    var hasCurrentFrame: Bool {
        currentFrame != nil
    }

    var hasRenderableFrame: Bool {
        currentFrame != nil || nextFrame != nil
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

    // MARK: - Playback

    func play() {
        guard !frames.isEmpty else { return }
        playbackTimer?.invalidate()
        isPlaying = true
        interactionState = .playing
        restartBackgroundPreloadIfNeeded()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
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

    func advanceFrame() {
        guard !frames.isEmpty else { return }
        let loaded = frames.map { $0 != nil }
        guard let nextIndex = nextLoadedIndex(in: loaded, after: currentFrameIndex) else {
            return
        }
        currentFrameIndex = nextIndex
    }

    /// Stops the internal Timer without changing `isPlaying` — the map layer's
    /// display link owns frame advancement while it runs (same ownership rule as
    /// the radar layer; both running would double-advance).
    func cancelInternalTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
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

    func loadLayer(_ layer: WeatherTileLayer) async {
        guard layer.imagePath != nil else { return }
        loadTask?.cancel()
        focusedLoadTask?.cancel()
        backgroundPreloadTask?.cancel()

        let sessionID = UUID()
        loadSessionID = sessionID

        currentLayer = layer
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
                // 1. Fetch frame list + bounds. The server sends max-age=600 + ETag,
                // so a revisit within the window is free and after it a 304
                // revalidation (still true under the generated client's transport).
                let decoded = try await APIClient.shared.modelFrames(model: layer.windFieldPrefix)
                guard !Task.isCancelled, self.loadSessionID == sessionID else { return }

                let fetchedFrameInfos = decoded.frames
                let fetchedBounds = decoded.image_bounds?.asDomain ?? decoded.bounds?.asDomain
                    ?? OscarRadarBounds(north: 85.051, south: -85.051, west: -180, east: 180)

                // 2. Pre-size array so the scrubber can render immediately.
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

                // Motion fields load in parallel and are optional — the layer
                // renders a plain cross-fade until they arrive (mirrors the radar
                // path). Precipitation only: temperature/wind never warp along
                // the precip flow, so they skip the fetch entirely.
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
                self.error = error.localizedDescription
            }
        }

        await loadTask?.value
    }

    /// Reload the active layer only when its metadata is old enough that the
    /// server can have new frames (or nothing ever loaded) — the
    /// foreground/periodic refresh hook. `loadLayer` resets and re-decodes
    /// everything, so a quick app switch must stay a no-op.
    func refreshIfStale() async {
        guard let layer = currentLayer, !isLoading else { return }
        if hasAnyLoadedFrame, let lastMetadataLoad,
           Date().timeIntervalSince(lastMetadataLoad) < Self.metadataStaleAfter {
            return
        }
        await loadLayer(layer)
    }

    // MARK: - Helpers

    /// Fetch + decode `/models/{model}/motion` (best-effort; nil on any failure).
    /// Byte-identical wire shape to `/radar/{region}/motion`, so the radar decoder
    /// parses it as-is. Server sends max-age 600 + ETag — refetches are cheap.
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

        focusedLoadTask?.cancel()
        guard let layer = currentLayer, layer.imagePath != nil else { return }
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
        guard allowsBackgroundPreload(for: renderMode),
              interactionState != .scrubbing,
              !isMapInteracting,
              let layer = currentLayer,
              layer.imagePath != nil,
              !frameInfos.isEmpty else { return }

        let sessionID = loadSessionID
        let focused = Set(focusedFrameIndices(around: currentFrameIndex))
        let ordered = prioritizedFrameIndices(count: frameInfos.count, around: currentFrameIndex)
            .filter { !focused.contains($0) }

        backgroundPreloadTask = Task { [weak self] in
            guard let self else { return }
            await self.loadFrameBatch(
                indices: ordered,
                sessionID: sessionID,
                layer: layer
            )
        }
    }

    private func focusedFrameIndices(around center: Int) -> [Int] {
        Array(prioritizedFrameIndices(count: frameInfos.count, around: center).prefix(renderMode.focusedPreloadCount))
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
                // A dry precip frame has no grid (404) — that's data ("no
                // precipitation"), not an error. Cache a 1×1 index-0 payload
                // (renders fully transparent) so scrubbing doesn't refetch it.
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
        playbackTimer?.invalidate()
    }
}

// MARK: - Motion morphing (per model)

extension WeatherTileLayer {
    /// Only precipitation morphs along the server flow field — temperature and
    /// wind cross-fade in data space (warping them along precip motion is wrong).
    var morphsAlongMotion: Bool {
        self == .iconPrecip || self == .ecmwfPrecip
    }
}
