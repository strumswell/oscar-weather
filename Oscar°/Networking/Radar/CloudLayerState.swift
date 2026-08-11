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

@MainActor
@Observable
final class CloudLayerState {

    nonisolated static let baseURL = radarBaseURL
    static let colormapId = "clouds"

    private(set) var frameKeys: [String] = []
    private(set) var frameTimestamps: [String] = []
    private(set) var bounds: OscarRadarBounds?
    /// Byte-identical wire shape to the radar motion payload.
    private(set) var motion: RadarMotionData?
    /// Bumped on metadata and every payload arrival — the coordinator's `syncAll`
    /// reads it in the observation preamble and re-syncs when loads land.
    private(set) var loadRevision = 0
    private(set) var isActive = false

    // MARK: Standalone timeline (TimelinePlayerState)
    //
    // Used only when clouds are the SELECTED layer (own scrubber through the
    // nowcast). In underlay mode the radar timeline stays the clock and these
    // stay idle.

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
    @ObservationIgnored nonisolated(unsafe) private var playbackTimer: Timer?
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

    /// Mirrors the radar metadata cache window.
    private static let metadataStaleAfter: TimeInterval = 10 * 60
    /// Decoded payloads kept around the anchor (≈3.6 MB each at the 2048 overview;
    /// ±14 covers the whole served series on a healthy device without approaching
    /// the radar state's budget).
    private static let residencyRadius = 14
    /// Frames fetched around the anchor per prefetch pass — clouds are the
    /// secondary consumer, one below the radar's focused window.
    private static let focusedCount = 4

    private static let instances = NSHashTable<CloudLayerState>.weakObjects()

    init() {
        Self.instances.add(self)
    }

    /// Resolved clouds palette: server `/colormaps/clouds` preferred, local
    /// fallback when unreachable (mirrors `OscarRadarState.resolvedPalette`).
    static func resolvedPalette() async -> [PixelRGBA] {
        await ModelGridLayerState.palette(for: colormapId) ?? localPalette
    }

    /// Kept in sync with oscar-server's `Colormaps.cloudsPalette256`: index 0
    /// transparent; 1…255 a cool blue-grey → near-white ramp, alpha 0→210.
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

    /// App-level memory-warning hook: keep only the frames beside each
    /// instance's last anchor; everything else reloads on demand.
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
        playbackTimer?.invalidate()
    }

    // MARK: - Activation

    /// Activate (fetch metadata, allow prefetch) or deactivate (cancel work,
    /// drop decoded frames, keep metadata for a cheap re-toggle).
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            isLoading = frameKeys.isEmpty
            loadMetadataIfStale()
        } else {
            pause()
            metadataTask?.cancel()
            prefetchTask?.cancel()
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
        playbackTimer?.invalidate()
        isPlaying = true
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceFrame()
            }
        }
    }

    func pause() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    func advanceFrame() {
        guard !frameKeys.isEmpty else { return }
        var loaded = [Bool](repeating: false, count: frameKeys.count)
        for index in loadedFrameIndices where loaded.indices.contains(index) { loaded[index] = true }
        guard let next = nextLoadedIndex(in: loaded, after: currentFrameIndex) else { return }
        currentFrameIndex = next
    }

    /// Stops the internal Timer without changing `isPlaying` — while playing,
    /// the map layer's display link owns frame advancement (both running would
    /// double-advance; same ownership rule as the radar/model layers).
    func cancelInternalTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
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

    /// The displayed frame (render anchor with selection fallback) plus its key.
    var currentFrameKeyed: (key: String, payload: RadarGridPayload)? {
        let index = renderFrameIndex ?? currentFrameIndex
        guard frameKeys.indices.contains(index), let payload = payloads[frameKeys[index]] else { return nil }
        return (frameKeys[index], payload)
    }

    /// The next loaded frame — the crossfade target in standalone playback.
    var nextFrameKeyed: (key: String, payload: RadarGridPayload)? {
        guard !frameKeys.isEmpty else { return nil }
        let anchor = renderFrameIndex ?? currentFrameIndex
        var loaded = [Bool](repeating: false, count: frameKeys.count)
        for index in loadedFrameIndices where loaded.indices.contains(index) { loaded[index] = true }
        guard let next = nextLoadedIndex(in: loaded, after: anchor),
              let payload = payloads[frameKeys[next]] else { return nil }
        return (frameKeys[next], payload)
    }

    /// True on the exact closest-to-now frame (the radar's LIVE convention).
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

    /// Foreground/staleness hook (WeatherMapDetailView's refresh loop).
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
            self?.metadataTask = nil
        }
    }

    private func loadMetadata(sessionID: UUID) async {
        guard let url = URL(string: "\(Self.baseURL)/clouds/meteosat/frames") else { return }
        var request = URLRequest(url: url)
        request.addAPIContactIdentity()
        let data: Data
        let http: HTTPURLResponse
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            data = body
            http = httpResponse
        } catch {
            guard loadSessionID == sessionID else { return }
            // Held frames keep serving through a failed refresh; only an empty
            // state surfaces the failure (mirrors OscarRadarState). Cancellation
            // (deactivating the layer mid-load) is not a failure.
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            if frameKeys.isEmpty, !cancelled {
                self.error = "Fehler beim Laden: \(error.localizedDescription)"
                isLoading = false
            }
            return
        }
        guard http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(RadarFramesResponse.self, from: data) else {
            guard loadSessionID == sessionID else { return }
            // 503 = server warming up, 404 = layer not configured — treat both as
            // "no cloud frames right now" and retry via the staleness loop.
            if http.statusCode == 503 || http.statusCode == 404 {
                lastMetadataLoad = Date()
            }
            if frameKeys.isEmpty {
                error = "Satellitenbilder sind derzeit nicht verfügbar."
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
        bounds = (decoded.imageBounds ?? decoded.bounds).asDomain
        lastMetadataLoad = Date()
        // Metadata replaced the key list; drop payloads for keys that vanished and
        // remap the index-based bookkeeping to the new ordering.
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
            guard let url = URL(string: "\(Self.baseURL)/clouds/meteosat/motion") else { return }
            var request = URLRequest(url: url)
            request.addAPIContactIdentity()
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            guard let self, self.loadSessionID == motionSession else { return }
            self.motion = RadarMotionData(jsonData: data)
            self.loadRevision += 1
        }
    }

    // MARK: - Payload access (coordinator-facing)

    func timestamp(forKey key: String) -> String? {
        guard let index = indexByKey[key], frameTimestamps.indices.contains(index) else { return nil }
        return frameTimestamps[index]
    }

    // MARK: - Prefetch

    /// Load frames around the anchor key (the current selection; exact match or
    /// nearest by date). Serial download+decode through the shared lane;
    /// thermally gated. A new anchor supersedes a running pass — the freshest
    /// position wins.
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
            self.prefetchTask = nil
            self.evict(around: self.lastAnchorIndex)
        }
    }

    private func nearestIndex(to key: String) -> Int {
        // Radar and cloud keys share the format, so lexicographic order is
        // chronological — nearest at-or-before wins.
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

        guard let url = URL(string: "\(Self.baseURL)/clouds/meteosat/frames/\(key)/grid") else { return }
        var request = URLRequest(url: url)
        request.addAPIContactIdentity()
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
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
