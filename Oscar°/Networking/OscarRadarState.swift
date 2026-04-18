import Foundation
import MapKit
import Observation
import UIKit

struct OscarRadarBounds: Equatable {
    let north: Double
    let south: Double
    let west: Double
    let east: Double
}

struct OscarRadarFrame: Identifiable {
    let id = UUID()
    let key: String
    let timestamp: String
    let cgImage: CGImage  // pre-decoded + pre-flipped for MapKit's CG coordinate system
}

enum MapRenderMode {
    case preview
    case fullscreen

    var focusedPreloadCount: Int {
        switch self {
        case .preview:
            3
        case .fullscreen:
            5
        }
    }

    var allowsBackgroundPreload: Bool {
        self == .fullscreen
    }
}

enum MapInteractionState {
    case idle
    case scrubbing
    case playing
}

private func closestTimestampIndex(in timestamps: [String]) -> Int {
    let now = Date()
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withInternetDateTime]
    let fmtFrac = ISO8601DateFormatter()
    fmtFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var bestIndex = 0
    var bestDiff = TimeInterval.infinity

    for (index, timestamp) in timestamps.enumerated() {
        let date = fmtFrac.date(from: timestamp)
            ?? fmt.date(from: timestamp)
            ?? Double(timestamp).map { Date(timeIntervalSince1970: $0) }
        guard let date else { continue }

        let diff = abs(now.timeIntervalSince(date))
        if diff < bestDiff {
            bestDiff = diff
            bestIndex = index
        }
    }

    return bestIndex
}

private func prioritizedFrameIndices(count: Int, around center: Int) -> [Int] {
    guard count > 0 else { return [] }

    let clampedCenter = max(0, min(count - 1, center))
    var ordered: [Int] = [clampedCenter]
    ordered.reserveCapacity(count)

    var step = 1
    while ordered.count < count {
        let right = clampedCenter + step
        if right < count {
            ordered.append(right)
        }

        let left = clampedCenter - step
        if left >= 0 {
            ordered.append(left)
        }

        step += 1
    }

    return ordered
}

private func nextLoadedIndex(in loaded: [Bool], after index: Int) -> Int? {
    guard !loaded.isEmpty else { return nil }

    let start = max(0, min(loaded.count - 1, index))
    var candidate = (start + 1) % loaded.count

    while candidate != start {
        if loaded[candidate] {
            return candidate
        }
        candidate = (candidate + 1) % loaded.count
    }

    return nil
}

private func contiguousLoadedRange(in loaded: [Bool], around anchor: Int?) -> ClosedRange<Int>? {
    guard !loaded.isEmpty, let anchor else { return nil }
    let clampedAnchor = max(0, min(loaded.count - 1, anchor))
    guard loaded[clampedAnchor] else { return nil }

    var lower = clampedAnchor
    while lower > 0, loaded[lower - 1] {
        lower -= 1
    }

    var upper = clampedAnchor
    while upper + 1 < loaded.count, loaded[upper + 1] {
        upper += 1
    }

    return lower...upper
}

private func allowsBackgroundPreload(for renderMode: MapRenderMode) -> Bool {
    guard renderMode.allowsBackgroundPreload else { return false }

    switch ProcessInfo.processInfo.thermalState {
    case .serious, .critical:
        return false
    default:
        return true
    }
}

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
    private(set) var renderFrameIndex: Int?
    private(set) var interactionState: MapInteractionState = .idle

    @ObservationIgnored private var playbackTimer: Timer?
    @ObservationIgnored private var frameInfos: [OscarFrameInfo] = []
    @ObservationIgnored private var loadSessionID = UUID()
    @ObservationIgnored private var suppressSelectionSideEffects = false
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundPreloadTask: Task<Void, Never>?
    @ObservationIgnored private var focusedLoadTask: Task<Void, Never>?
    @ObservationIgnored private let renderMode: MapRenderMode
    private static let baseURL = radarBaseURL
    private static let cacheLock = NSLock()

    init(renderMode: MapRenderMode = .fullscreen) {
        self.renderMode = renderMode
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
        guard !frameTimestamps.isEmpty else { return false }
        return currentFrameIndex == closestTimestampIndex(in: frameTimestamps)
    }

    var hasAnyLoadedFrame: Bool {
        frames.contains { $0 != nil }
    }

    var isSelectedFrameReady: Bool {
        frames.indices.contains(currentFrameIndex) && frames[currentFrameIndex] != nil
    }

    var loadedFrameIndices: Set<Int> {
        Set(frames.indices.filter { frames[$0] != nil })
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

    // MARK: - Shared Cache

    private static var cachedFrameInfos: [OscarFrameInfo] = []
    private static var cachedBounds: OscarBoundsInfo?
    private static var cachedImages: [String: CGImage] = [:]
    private static var lastFetchedTime: Date?
    private static let cacheDuration: TimeInterval = 10 * 60

    private static var isCacheValid: Bool {
        guard let last = lastFetchedTime else { return false }
        return Date().timeIntervalSince(last) < cacheDuration
    }

    static func purgeDecodedCaches() {
        cacheLock.withLock {
            cachedImages.removeAll()
        }
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
                let (fetchedFrameInfos, boundsInfo) = try await Self.fetchFrameInfos()
                guard !Task.isCancelled, self.loadSessionID == sessionID else { return }
                guard !fetchedFrameInfos.isEmpty else {
                    self.isLoading = false
                    return
                }

                let timestamps = fetchedFrameInfos.map(\.timestamp)
                let closest = closestTimestampIndex(in: timestamps)

                self.suppressSelectionSideEffects = true
                self.bounds = boundsInfo.asDomain
                self.frameInfos = fetchedFrameInfos
                self.frameTimestamps = timestamps
                self.frames = Array(repeating: nil, count: fetchedFrameInfos.count)
                self.currentFrameIndex = closest
                self.suppressSelectionSideEffects = false

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
              !frameInfos.isEmpty else { return }

        let sessionID = loadSessionID
        let focused = Set(focusedFrameIndices(around: currentFrameIndex))
        let ordered = prioritizedFrameIndices(count: frameInfos.count, around: currentFrameIndex)
            .filter { !focused.contains($0) }

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

    private func loadFrameBatch(indices: [Int], sessionID: UUID) async {
        for index in indices {
            guard !Task.isCancelled else { return }
            _ = await loadFrameIfNeeded(at: index, sessionID: sessionID)
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

        guard let cgImage = await Self.loadImage(for: frameInfos[index]),
              loadSessionID == sessionID,
              frameInfos.indices.contains(index),
              frames.indices.contains(index) else {
            return false
        }

        var updated = frames
        let info = frameInfos[index]
        updated[index] = OscarRadarFrame(
            key: info.key,
            timestamp: info.timestamp,
            cgImage: cgImage
        )
        frames = updated

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
    private static func fetchFrameInfos() async throws -> ([OscarFrameInfo], OscarBoundsInfo) {
        if let cached = cacheLock.withLock({
            if isCacheValid, let bounds = cachedBounds, !cachedFrameInfos.isEmpty {
                return (cachedFrameInfos, bounds)
            }
            cachedImages.removeAll()
            return nil
        }) {
            return cached
        }

        guard let url = URL(string: "\(baseURL)/radar/frames") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.addAPIContactIdentity()
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OscarFramesResponse.self, from: data)
        cacheLock.withLock {
            cachedFrameInfos = response.frames
            cachedBounds = response.bounds
            lastFetchedTime = Date()
        }
        return (response.frames, response.bounds)
    }

    /// Returns a cached CGImage for the frame, or downloads and caches it if missing.
    private static func loadImage(for frameInfo: OscarFrameInfo) async -> CGImage? {
        if let cached = cacheLock.withLock({ cachedImages[frameInfo.key] }) {
            return cached
        }

        guard let url = URL(string: "\(baseURL)/radar/image/\(frameInfo.key).webp?cmap=plasma") else { return nil }
        do {
            var request = URLRequest(url: url)
            request.addAPIContactIdentity()
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let uiImage = UIImage(data: data) else { return nil }
            guard let cgImage = prepareForRenderer(uiImage) else { return nil }
            cacheLock.withLock {
                cachedImages[frameInfo.key] = cgImage
            }
            return cgImage
        } catch {
            return nil
        }
    }

    /// Force-decodes a UIImage into a raw CGBitmapContext and flips it vertically.
    ///
    /// MapKit's overlay renderer uses a standard CG coordinate system (y going up),
    /// so `context.draw(cgImage, in:)` places the image's row 0 at the BOTTOM of the
    /// rect. By pre-flipping here (on a background thread at load time), the renderer's
    /// draw() needs no transform and no UIGraphicsPushContext — just a direct CG draw.
    static func prepareForRenderer(_ image: UIImage) -> CGImage? {
        guard let cgImage = image.cgImage else { return nil }
        let w = cgImage.width, h = cgImage.height
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: cs, bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return ctx.makeImage()
    }

    deinit {
        bootstrapTask?.cancel()
        focusedLoadTask?.cancel()
        backgroundPreloadTask?.cancel()
        playbackTimer?.invalidate()
    }
}

// MARK: - API Models

private struct OscarFramesResponse: Decodable {
    let frames: [OscarFrameInfo]
    let bounds: OscarBoundsInfo
}

private struct OscarFrameInfo: Decodable {
    let key: String
    let timestamp: String
}

private struct OscarBoundsInfo: Decodable {
    let north: Double
    let south: Double
    let west: Double
    let east: Double

    var asDomain: OscarRadarBounds {
        OscarRadarBounds(north: north, south: south, west: west, east: east)
    }
}

// ===========================================================================
// MARK: - Tile Layer System (ICON-D2 / GFS)
// ===========================================================================

// Typed accessor for SettingService — lives here so it's only compiled
// in targets that include both SettingService and WeatherTileLayer.
extension SettingService {
    var activeTileLayer: WeatherTileLayer? {
        get { activeTileLayerRaw.flatMap { WeatherTileLayer(rawValue: $0) } }
        set { activeTileLayerRaw = newValue?.rawValue }
    }
}

// MARK: WeatherTileLayer

enum WeatherTileLayer: String, CaseIterable, Hashable {
    case iconPrecip = "icon_precip"
    case iconTemp   = "icon_temp"
    case iconWind   = "icon_wind"
    case gfsPrecip  = "gfs_precip"
    case gfsTemp    = "gfs_temp"
    case gfsWind    = "gfs_wind"

    var framesEndpoint: String {
        switch self {
        case .iconPrecip, .iconTemp, .iconWind: return "icon/frames"
        case .gfsPrecip, .gfsTemp, .gfsWind:   return "gfs/frames"
        }
    }

    var tilePath: String {
        switch self {
        case .iconPrecip: return "icon/precip-tiles"
        case .iconTemp:   return "icon/temp-tiles"
        case .iconWind:   return "icon/wind-tiles"
        case .gfsPrecip:  return "gfs/prate-tiles"
        case .gfsTemp:    return "gfs/temp-tiles"
        case .gfsWind:    return "gfs/wind-tiles"
        }
    }

    /// Full-world image endpoint path for each layer.
    var imagePath: String? {
        switch self {
        case .iconPrecip: return "icon/precip-image"
        case .iconTemp:   return "icon/temp-image"
        case .iconWind:   return "icon/wind-image"
        case .gfsPrecip:  return "gfs/prate-image"
        case .gfsTemp:    return "gfs/temp-image"
        case .gfsWind:    return "gfs/wind-image"
        }
    }

    var sourceLabel: String {
        switch self {
        case .iconPrecip, .iconTemp, .iconWind: return "DWD ICON-D2"
        case .gfsPrecip, .gfsTemp, .gfsWind:   return "NOAA GFS"
        }
    }
}

// MARK: - GFS Full-World Image Layer State

let radarBaseURL = "https://radar.oscars.love"

@MainActor
@Observable
final class GFSImageLayerState {

    static let baseURL = radarBaseURL

    // Pre-sized when metadata arrives; slots fill in as images download.
    private(set) var frames: [CGImage?] = []
    private(set) var frameTimestamps: [String] = []
    private(set) var frameKeys: [String] = []
    private(set) var bounds: OscarRadarBounds?
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
    private(set) var renderFrameIndex: Int?
    private(set) var interactionState: MapInteractionState = .idle

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundPreloadTask: Task<Void, Never>?
    @ObservationIgnored private var focusedLoadTask: Task<Void, Never>?
    @ObservationIgnored private var playbackTimer: Timer?
    @ObservationIgnored private var frameInfos: [TileFrameInfo] = []
    @ObservationIgnored private var loadSessionID = UUID()
    @ObservationIgnored private var suppressSelectionSideEffects = false
    @ObservationIgnored private let renderMode: MapRenderMode

    // Shared across instances — survives layer switches.
    private static let cacheLock = NSLock()
    private static var imageCache: [String: CGImage] = [:]

    static func purgeDecodedCaches() {
        cacheLock.withLock {
            imageCache.removeAll()
        }
    }

    init(renderMode: MapRenderMode = .fullscreen) {
        self.renderMode = renderMode
    }

    // MARK: - Derived

    var currentFrame: CGImage? {
        frame(at: renderFrameIndex ?? currentFrameIndex)
    }

    var nextFrame: CGImage? {
        guard let anchor = renderFrameIndex ?? (isSelectedFrameReady ? currentFrameIndex : nil) else { return nil }
        let loaded = frames.map { $0 != nil }
        guard let nextIndex = nextLoadedIndex(in: loaded, after: anchor) else { return nil }
        return frame(at: nextIndex)
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

    var loadedFrameIndices: Set<Int> {
        Set(frames.indices.filter { frames[$0] != nil })
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

    func beginScrubbing() {
        interactionState = .scrubbing
        backgroundPreloadTask?.cancel()
    }

    func endScrubbing() {
        interactionState = isPlaying ? .playing : .idle
        restartBackgroundPreloadIfNeeded()
    }

    // MARK: - Load

    func loadLayer(_ layer: WeatherTileLayer) async {
        guard let imagePath = layer.imagePath else { return }
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
        frameKeys = []
        frameInfos = []
        bounds = OscarRadarBounds(north: 85.051, south: -85.051, west: -180, east: 180)
        loadingFrameIndices.removeAll()
        renderFrameIndex = nil

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 1. Fetch frame list + bounds
                guard let url = URL(string: "\(Self.baseURL)/\(layer.framesEndpoint)") else { return }
                var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                req.addAPIContactIdentity()
                let (data, _) = try await URLSession.shared.data(for: req)
                let decoded = try JSONDecoder().decode(TileFramesResponse.self, from: data)
                guard !Task.isCancelled, self.loadSessionID == sessionID else { return }

                let fetchedFrameInfos = decoded.frames
                let fetchedBounds: OscarRadarBounds
                if let b = decoded.imageBounds ?? decoded.bounds {
                    fetchedBounds = OscarRadarBounds(north: b.north, south: b.south, west: b.west, east: b.east)
                } else {
                    fetchedBounds = OscarRadarBounds(north: 85.051, south: -85.051, west: -180, east: 180)
                }

                // 2. Pre-size array so the scrubber can render immediately.
                let timestamps = fetchedFrameInfos.map(\.validTime)
                let keys = fetchedFrameInfos.map(\.key)
                let closest = closestTimestampIndex(in: timestamps)

                self.suppressSelectionSideEffects = true
                self.frameInfos = fetchedFrameInfos
                self.frames = Array(repeating: nil, count: fetchedFrameInfos.count)
                self.frameTimestamps = timestamps
                self.frameKeys = keys
                self.bounds = fetchedBounds
                self.currentFrameIndex = closest
                self.suppressSelectionSideEffects = false

                await self.loadFrameBatch(
                    indices: self.focusedFrameIndices(around: closest),
                    sessionID: sessionID,
                    imagePath: imagePath,
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

    // MARK: - Helpers

    private func handleFrameSelectionChanged() {
        guard !suppressSelectionSideEffects else { return }
        guard !frameInfos.isEmpty,
              currentLayer != nil,
              frameInfos.indices.contains(currentFrameIndex) else { return }

        if isSelectedFrameReady {
            renderFrameIndex = currentFrameIndex
        }

        focusedLoadTask?.cancel()
        guard let layer = currentLayer, let imagePath = layer.imagePath else { return }
        let sessionID = loadSessionID
        let focusIndices = focusedFrameIndices(around: currentFrameIndex)

        focusedLoadTask = Task { [weak self] in
            guard let self else { return }
            await self.loadFrameBatch(
                indices: focusIndices,
                sessionID: sessionID,
                imagePath: imagePath,
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
              let layer = currentLayer,
              let imagePath = layer.imagePath,
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
                imagePath: imagePath,
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
        imagePath: String,
        layer: WeatherTileLayer
    ) async {
        for index in indices {
            guard !Task.isCancelled else { return }
            _ = await loadFrameIfNeeded(
                at: index,
                sessionID: sessionID,
                imagePath: imagePath,
                layer: layer
            )
        }
    }

    private func loadFrameIfNeeded(
        at index: Int,
        sessionID: UUID,
        imagePath: String,
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

        let cached = Self.cacheLock.withLock { Self.imageCache[cacheKey] }

        let cgImage: CGImage?
        if let cached {
            cgImage = cached
        } else {
            guard !Task.isCancelled,
                  let url = URL(string: "\(Self.baseURL)/\(imagePath)/\(info.key)") else {
                return false
            }
            var req = URLRequest(url: url)
            req.addAPIContactIdentity()
            guard let (data, response) = try? await URLSession.shared.data(for: req),
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let uiImage = UIImage(data: data),
                  let decoded = OscarRadarState.prepareForRenderer(uiImage) else {
                return false
            }
            Self.cacheLock.withLock {
                Self.imageCache[cacheKey] = decoded
            }
            cgImage = decoded
        }

        guard let cgImage,
              loadSessionID == sessionID,
              currentLayer == layer,
              frames.indices.contains(index) else {
            return false
        }

        var updated = frames
        updated[index] = cgImage
        frames = updated

        if renderFrameIndex == nil || currentFrameIndex == index {
            renderFrameIndex = index
        }

        if isLoading, hasAnyLoadedFrame {
            isLoading = false
        }

        return true
    }

    private func frame(at index: Int?) -> CGImage? {
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

// MARK: - API Models (tile layers)

private struct TileFramesResponse: Decodable {
    let frames: [TileFrameInfo]
    let bounds: TileBounds?
    let imageBounds: TileBounds?

    enum CodingKeys: String, CodingKey {
        case frames
        case bounds
        case imageBounds = "image_bounds"
    }

    struct TileBounds: Decodable {
        let north, south, west, east: Double
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frames = try container.decode([TileFrameInfo].self, forKey: .frames)
        bounds = try? container.decode(TileBounds.self, forKey: .bounds)
        imageBounds = try? container.decode(TileBounds.self, forKey: .imageBounds)
    }
}

private struct TileFrameInfo: Decodable {
    let key: String
    let validTime: String
}
