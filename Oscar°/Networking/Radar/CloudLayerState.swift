//
//  CloudLayerState.swift
//  Oscar°
//
//  Frame store for the satellite cloud layer (`/clouds/meteosat`, SEVIRI IR
//  full disk): a selectable layer with its own scrubbable timeline and playback,
//  the model-layer shape on the radar wire format (5-min series + nowcast).
//

import Foundation
import Observation
import OpenAPIRuntime

@MainActor
@Observable
final class CloudLayerState {

    static let colormapId = "clouds"

    private(set) var frameKeys: [String] = []
    private(set) var frameTimestamps: [String] = []
    private(set) var bounds: OscarRadarBounds?
    private(set) var motion: RadarMotionData?
    private(set) var loadRevision = 0
    private(set) var isActive = false

    // MARK: Standalone timeline (TimelinePlayerState)

    var currentFrameIndex: Int = 0 {
        didSet {
            guard currentFrameIndex != oldValue else { return }
            handleSelectionChanged()
        }
    }
    private(set) var renderFrameIndex: Int?
    private(set) var isPlaying = false
    var isLoading = false
    var error: String?
    private(set) var loadedFrameIndices: Set<Int> = []
    private(set) var loadingFrameIndices: Set<Int> = []
    var hasAnyLoadedFrame: Bool { !loadedFrameIndices.isEmpty }
    @ObservationIgnored private let playback = PlaybackTicker()
    @ObservationIgnored private var suppressSelectionSideEffects = false

    @ObservationIgnored private var frameDates: [Date?] = []
    @ObservationIgnored private var indexByKey: [String: Int] = [:]
    @ObservationIgnored private var payloads: [String: RadarGridPayload] = [:]
    @ObservationIgnored private var loadingKeys: Set<String> = []
    @ObservationIgnored private var metadataTask: Task<Void, Never>?
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var lastMetadataLoad: Date?
    @ObservationIgnored private var loadSessionID = UUID()
    @ObservationIgnored private var lastAnchorIndex = 0

    private static let metadataStaleAfter: TimeInterval = 10 * 60
    private static let residencyBudget = adaptiveCacheBudget(
        fraction: 0.06, floor: 32 * 1024 * 1024, cap: 100 * 1024 * 1024)
    private static let residencyRadius = max(4, residencyBudget / 3_600_000 / 2)
    private static let focusedCount = 4

    private static let instances = NSHashTable<CloudLayerState>.weakObjects()

    init() {
        Self.instances.add(self)
    }

    static func resolvedPalette() async -> [PixelRGBA] {
        await ServerPalettes.resolve(id: colormapId) ?? localPalette
    }

    static let localPalette: [PixelRGBA] = {
        func mix(_ a: Double, _ b: Double, _ t: Double) -> UInt8 {
            UInt8(clamping: Int((a + (b - a) * t).rounded()))
        }
        var out = [PixelRGBA(r: 0, g: 0, b: 0, a: 0)]
        out.reserveCapacity(256)
        for i in 1..<256 {
            let t = Double(i) / 255
            out.append(PixelRGBA(
                r: mix(0xdf, 0xfb, t),
                g: mix(0xe5, 0xfd, t),
                b: mix(0xec, 0xff, t),
                a: mix(0, 210, pow(t, 0.85))))
        }
        return out
    }()

    static func purgeDecodedCaches() {
        for state in instances.allObjects {
            state.prefetchTask?.cancel()
            let anchor = state.lastAnchorIndex
            state.payloads = state.payloads.filter { key, _ in
                guard let index = state.indexByKey[key] else { return false }
                return abs(index - anchor) <= 1
            }
            state.loadedFrameIndices = Set(state.payloads.keys.compactMap { state.indexByKey[$0] })
        }
    }

    deinit {
        metadataTask?.cancel()
        prefetchTask?.cancel()
    }

    // MARK: - Activation

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            isLoading = frameKeys.isEmpty
            loadMetadataIfStale()
        } else {
            pause()
            metadataTask?.cancel()
            metadataTask = nil
            prefetchTask?.cancel()
            prefetchTask = nil
            loadingKeys.removeAll()
            loadingFrameIndices.removeAll()
            payloads.removeAll()
            loadedFrameIndices.removeAll()
            renderFrameIndex = nil
            isLoading = false
            error = nil
        }
    }

    // MARK: - Playback (standalone mode)

    func play() {
        guard !frameKeys.isEmpty else { return }
        isPlaying = true
        playback.start(interval: .milliseconds(500)) { [weak self] in self?.advanceFrame() }
    }

    func pause() {
        isPlaying = false
        playback.stop()
    }

    func advanceFrame() {
        guard !frameKeys.isEmpty else { return }
        var loaded = [Bool](repeating: false, count: frameKeys.count)
        for index in loadedFrameIndices where loaded.indices.contains(index) { loaded[index] = true }
        guard let next = nextLoadedIndex(in: loaded, after: currentFrameIndex) else { return }
        currentFrameIndex = next
    }

    func cancelInternalTimer() {
        playback.stop()
    }

    func beginScrubbing() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    func endScrubbing() {
        handleSelectionChanged()
    }

    func beginMapInteraction() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    func endMapInteraction() {
        guard isActive else { return }
        handleSelectionChanged()
    }

    var currentFrameKeyed: (key: String, payload: RadarGridPayload)? {
        let index = renderFrameIndex ?? currentFrameIndex
        guard frameKeys.indices.contains(index), let payload = payloads[frameKeys[index]] else { return nil }
        return (frameKeys[index], payload)
    }

    var nextFrameKeyed: (key: String, payload: RadarGridPayload)? {
        guard !frameKeys.isEmpty else { return nil }
        let anchor = renderFrameIndex ?? currentFrameIndex
        var loaded = [Bool](repeating: false, count: frameKeys.count)
        for index in loadedFrameIndices where loaded.indices.contains(index) { loaded[index] = true }
        guard let next = nextLoadedIndex(in: loaded, after: anchor),
              let payload = payloads[frameKeys[next]] else { return nil }
        return (frameKeys[next], payload)
    }

    var isCurrentFrameLive: Bool {
        guard !frameKeys.isEmpty else { return false }
        return currentFrameIndex == closestTimestampIndex(in: frameDates)
    }

    private func handleSelectionChanged() {
        guard !suppressSelectionSideEffects, frameKeys.indices.contains(currentFrameIndex) else { return }
        if loadedFrameIndices.contains(currentFrameIndex) {
            renderFrameIndex = currentFrameIndex
        }
        prefetch(aroundKey: frameKeys[currentFrameIndex])
    }

    func refreshIfStale() {
        guard isActive else { return }
        loadMetadataIfStale()
    }

    private func loadMetadataIfStale() {
        if let lastMetadataLoad, Date().timeIntervalSince(lastMetadataLoad) < Self.metadataStaleAfter,
           !frameKeys.isEmpty {
            return
        }
        guard metadataTask == nil else { return }
        let sessionID = UUID()
        loadSessionID = sessionID
        metadataTask = Task { [weak self] in
            await self?.loadMetadata(sessionID: sessionID)
            if self?.loadSessionID == sessionID { self?.metadataTask = nil }
        }
    }

    private func loadMetadata(sessionID: UUID) async {
        let decoded: RadarFramesResponse
        do {
            guard let response = try await APIClient.shared.cloudFrames() else {
                guard loadSessionID == sessionID else { return }
                lastMetadataLoad = Date()
                if frameKeys.isEmpty {
                    error = String(localized: "Satellitenbilder sind derzeit nicht verfügbar.")
                    isLoading = false
                }
                return
            }
            decoded = response
        } catch {
            guard loadSessionID == sessionID else { return }
            let cause = (error as? ClientError)?.underlyingError ?? error
            let cancelled = cause is CancellationError || (cause as? URLError)?.code == .cancelled
            if frameKeys.isEmpty, !cancelled {
                if (cause as? URLError)?.code == .badServerResponse || cause is DecodingError {
                    self.error = String(localized: "Satellitenbilder sind derzeit nicht verfügbar.")
                } else {
                    self.error = String(localized: "Fehler beim Laden: \(cause.localizedDescription)")
                }
                isLoading = false
            }
            return
        }
        guard loadSessionID == sessionID else { return }
        error = nil

        let keys = decoded.frames.map(\.key)
        let timestamps = decoded.frames.map(\.timestamp)
        suppressSelectionSideEffects = true
        frameKeys = keys
        frameTimestamps = timestamps
        frameDates = timestamps.map(parseFrameDate)
        indexByKey = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0) })
        bounds = (decoded.image_bounds ?? decoded.bounds).asDomain
        lastMetadataLoad = Date()
        payloads = payloads.filter { indexByKey[$0.key] != nil }
        loadedFrameIndices = Set(payloads.keys.compactMap { indexByKey[$0] })
        loadingFrameIndices = Set(loadingKeys.compactMap { indexByKey[$0] })
        currentFrameIndex = closestTimestampIndex(in: frameDates)
        renderFrameIndex = loadedFrameIndices.contains(currentFrameIndex) ? currentFrameIndex : nil
        suppressSelectionSideEffects = false
        isLoading = payloads.isEmpty
        loadRevision += 1
        handleSelectionChanged()

        let motionSession = sessionID
        Task { [weak self] in
            guard let payload = try? await APIClient.shared.cloudMotion() else { return }
            guard let self, self.loadSessionID == motionSession else { return }
            self.motion = RadarMotionData(payload: payload)
            self.loadRevision += 1
        }
    }

    // MARK: - Payload access (coordinator-facing)

    func timestamp(forKey key: String) -> String? {
        guard let index = indexByKey[key], frameTimestamps.indices.contains(index) else { return nil }
        return frameTimestamps[index]
    }

    // MARK: - Prefetch

    func prefetch(aroundKey key: String) {
        guard isActive, !frameKeys.isEmpty else { return }
        let anchor = indexByKey[key] ?? nearestIndex(to: key)
        if anchor == lastAnchorIndex, prefetchTask != nil { return }
        lastAnchorIndex = anchor
        prefetchTask?.cancel()

        let thermal = ProcessInfo.processInfo.thermalState
        guard thermal != .critical else { return }
        let wanted = prioritizedFrameIndices(count: frameKeys.count, around: anchor)
        let count = thermal == .nominal ? wanted.count : Self.focusedCount
        let indices = Array(wanted.prefix(count)).filter { index in
            let frameKey = frameKeys[index]
            return payloads[frameKey] == nil && !loadingKeys.contains(frameKey)
        }
        guard !indices.isEmpty else { return }

        let sessionID = loadSessionID
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            for index in indices.prefix(Self.focusedCount * 4) {
                guard !Task.isCancelled, self.loadSessionID == sessionID else { break }
                await self.loadFrame(at: index, sessionID: sessionID)
            }
            if self.loadSessionID == sessionID { self.prefetchTask = nil }
            self.evict(around: self.lastAnchorIndex)
        }
    }

    private func nearestIndex(to key: String) -> Int {
        var best = 0
        for (index, frameKey) in frameKeys.enumerated() where frameKey <= key {
            best = index
        }
        return best
    }

    private func loadFrame(at index: Int, sessionID: UUID) async {
        guard frameKeys.indices.contains(index) else { return }
        let key = frameKeys[index]
        guard payloads[key] == nil, !loadingKeys.contains(key) else { return }
        loadingKeys.insert(key)
        loadingFrameIndices.insert(index)
        defer {
            loadingKeys.remove(key)
            loadingFrameIndices.remove(index)
        }

        guard let data = try? await APIClient.shared.cloudGrid(key: key) else { return }
        guard let payload = await RadarFrameDecodeLane.shared.decodeGrid(data) else { return }
        guard loadSessionID == sessionID, indexByKey[key] == index else { return }
        payloads[key] = payload
        loadedFrameIndices.insert(index)
        if renderFrameIndex == nil || currentFrameIndex == index {
            renderFrameIndex = index
        }
        isLoading = false
        loadRevision += 1
    }

    private func evict(around anchor: Int) {
        payloads = payloads.filter { key, _ in
            guard let index = indexByKey[key] else { return false }
            return abs(index - anchor) <= Self.residencyRadius
        }
        loadedFrameIndices = Set(payloads.keys.compactMap { indexByKey[$0] })
    }
}
