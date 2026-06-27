import Foundation
import MapKit
import Metal
import Observation
import UIKit

struct OscarRadarBounds: Equatable {
    let north: Double
    let south: Double
    let west: Double
    let east: Double
}

/// Radar coverage the user can choose between in the map's layer menu.
/// Mirrors oscar-server's two radar sources: high-res DWD (Germany) and the
/// pan-European EUMETNET OPERA composite.
enum RadarRegion: String, CaseIterable, Equatable, Sendable {
    case germany
    case europe

    /// Path component used in oscar-server radar URLs (`/radar/{pathComponent}/…`).
    var pathComponent: String { rawValue }
}

@MainActor
final class OscarRadarFrame: Identifiable {
    let id = UUID()
    let key: String
    let timestamp: String

    private enum Source {
        case image(CGImage)                                   // raster path: ready to draw
        case grid(indices: [UInt8], width: Int, height: Int)  // grid path: 8-bit, colormap on demand
    }
    private let source: Source

    init(key: String, timestamp: String, cgImage: CGImage) {
        self.key = key; self.timestamp = timestamp; self.source = .image(cgImage)
    }
    init(key: String, timestamp: String, gridIndices: [UInt8], width: Int, height: Int) {
        self.key = key; self.timestamp = timestamp
        self.source = .grid(indices: gridIndices, width: width, height: height)
    }

    /// Cost-bounded cache of materialized RGBA images for grid frames, so the heavy decoded
    /// bitmaps exist only for a sliding window of frames while `frames` holds the compact
    /// 8-bit buffers — that's the whole RAM win. Sized (by bytes) to cover a realistic scrub
    /// window so dragging through the timeline hits warm images instead of recolormapping;
    /// frames outside the window are re-materialized off-main by the load pipeline when the
    /// playhead nears them. Keyed by frame key (grid is Germany-only, so keys don't collide).
    private static let materializedImages: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 96 * 1024 * 1024   // ~18 DWD frames at 1.3 MP; bounded
        return cache
    }()

    static func purgeMaterialized() { materializedImages.removeAllObjects() }

    /// True when `cgImage` can return without doing any colormap work: raster frames are
    /// always ready; grid frames only once their RGBA image is cached. The load pipeline
    /// uses this to decide whether a frame still needs off-main materialization.
    var isReadyToDraw: Bool {
        switch source {
        case .image: return true
        case .grid: return Self.materializedImages.object(forKey: key as NSString) != nil
        }
    }

    /// The drawable image. Raster frames return their decoded image directly; grid frames
    /// return their cached materialized image. The CPU colormap here is only a last-resort
    /// fallback for the rare case the render path reaches a grid frame before the pipeline
    /// has materialized it (see `ensureMaterialized`) — normal scrubbing never hits it.
    var cgImage: CGImage? {
        switch source {
        case .image(let image):
            return image
        case .grid(let indices, let width, let height):
            if let cached = Self.materializedImages.object(forKey: key as NSString) { return cached }
            guard let image = OscarRadarState.colormapIndices(indices, width: width, height: height) else { return nil }
            Self.materializedImages.setObject(image, forKey: key as NSString, cost: width * height * 4)
            return image
        }
    }

    /// Colormaps this grid frame's index buffer on the GPU (off the main thread) and caches
    /// the result, so the render path only ever reads a ready image. No-op for raster frames
    /// or when already cached. Called from the load/preload pipeline — never the draw path.
    func ensureMaterialized() async {
        guard case let .grid(indices, width, height) = source,
              Self.materializedImages.object(forKey: key as NSString) == nil else { return }
        let palette = await OscarRadarState.resolvedPalette()
        guard let image = await RadarGridColormapper.makeImage(
            indices: indices, width: width, height: height, palette: palette) else { return }
        Self.materializedImages.setObject(image, forKey: key as NSString, cost: width * height * 4)
    }
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

private enum FrameDateParser {
    static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private func parseFrameDate(_ timestamp: String) -> Date? {
    FrameDateParser.fractional.date(from: timestamp)
        ?? FrameDateParser.plain.date(from: timestamp)
        ?? Double(timestamp).map { Date(timeIntervalSince1970: $0) }
}

private func closestTimestampIndex(in dates: [Date?]) -> Int {
    let now = Date()
    var bestIndex = 0
    var bestDiff = TimeInterval.infinity

    for (index, date) in dates.enumerated() {
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
    /// Active radar coverage (DWD Germany vs. OPERA Europe). Use `setRegion(_:)`
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
    private(set) var renderFrameIndex: Int?
    private(set) var interactionState: MapInteractionState = .idle
    private(set) var isMapInteracting = false

    @ObservationIgnored private var playbackTimer: Timer?
    @ObservationIgnored private var frameInfos: [OscarFrameInfo] = []
    @ObservationIgnored private var frameDates: [Date?] = []
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
        guard !frameDates.isEmpty else { return false }
        return currentFrameIndex == closestTimestampIndex(in: frameDates)
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

    // Keyed by region: frame keys are bare timestamps that collide across
    // germany/europe, so caches must be region-qualified.
    private static var cachedFrameInfos: [RadarRegion: [OscarFrameInfo]] = [:]
    private static var cachedBounds: [RadarRegion: OscarBoundsInfo] = [:]
    private static let imageCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()
    private static var lastFetchedTime: [RadarRegion: Date] = [:]
    private static let cacheDuration: TimeInterval = 10 * 60

    private static func isCacheValid(for region: RadarRegion) -> Bool {
        guard let last = lastFetchedTime[region] else { return false }
        return Date().timeIntervalSince(last) < cacheDuration
    }

    static func purgeDecodedCaches() {
        imageCache.removeAllObjects()
        OscarRadarFrame.purgeMaterialized()
    }

    // MARK: - Region

    /// Switches radar coverage. Clears the loaded frames + in-flight work so the
    /// next `loadCurrentFrame()`/`loadAllFrames()` fetches the new region. No-op
    /// if the region is unchanged.
    func setRegion(_ newRegion: RadarRegion) {
        guard newRegion != region else { return }
        region = newRegion

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
        loadingFrameIndices.removeAll()
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
                let (fetchedFrameInfos, boundsInfo) = try await Self.fetchFrameInfos(region: self.region)
                guard !Task.isCancelled, self.loadSessionID == sessionID else { return }
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
              !isMapInteracting,
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

        if let existing = frames[index] {
            if renderFrameIndex == nil {
                renderFrameIndex = index
            }
            // Re-warm grid frames whose materialized image was evicted from the window cache,
            // off-main, so the playhead never reaches one that needs a main-thread colormap.
            if !existing.isReadyToDraw {
                await existing.ensureMaterialized()
            }
            return true
        }

        if loadingFrameIndices.contains(index) {
            return false
        }

        loadingFrameIndices.insert(index)
        defer { loadingFrameIndices.remove(index) }

        let info = frameInfos[index]
        // Grid path is Germany/DWD only for now; Europe always uses the raster image.
        let useGrid = UserDefaults.standard.bool(forKey: "radarUsesValueGrid") && region == .germany

        let loadedFrame: OscarRadarFrame?
        if useGrid {
            await Self.warmPalette()
            if let grid = await Self.loadGridIndices(for: info, region: region) {
                loadedFrame = OscarRadarFrame(key: info.key, timestamp: info.timestamp,
                                              gridIndices: grid.indices, width: grid.width, height: grid.height)
            } else {
                loadedFrame = nil
            }
        } else if let image = await Self.loadRasterImage(for: info, region: region) {
            loadedFrame = OscarRadarFrame(key: info.key, timestamp: info.timestamp, cgImage: image)
        } else {
            loadedFrame = nil
        }

        guard let loadedFrame,
              loadSessionID == sessionID,
              frameInfos.indices.contains(index),
              frames.indices.contains(index) else {
            return false
        }

        // Colormap grid frames on the GPU off-main *before* publishing them, so the render
        // path only ever reads a ready image (no-op for raster). The await can suspend, so
        // re-validate the session/array afterwards.
        await loadedFrame.ensureMaterialized()
        guard loadSessionID == sessionID, frames.indices.contains(index) else { return false }

        var updated = frames
        updated[index] = loadedFrame
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
    private static func fetchFrameInfos(region: RadarRegion) async throws -> ([OscarFrameInfo], OscarBoundsInfo) {
        if let cached = cacheLock.withLock({ () -> ([OscarFrameInfo], OscarBoundsInfo)? in
            if isCacheValid(for: region),
               let bounds = cachedBounds[region],
               let infos = cachedFrameInfos[region], !infos.isEmpty {
                return (infos, bounds)
            }
            return nil
        }) {
            return cached
        }

        guard let url = URL(string: "\(baseURL)/radar/\(region.pathComponent)/frames") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.addAPIContactIdentity()
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OscarFramesResponse.self, from: data)
        // The image is rendered in Web Mercator; `image_bounds` is the lat/lon of
        // that Mercator rectangle and is what the overlay must span. `bounds` is
        // the tighter data footprint and would misproject the image — most visibly
        // for the large OPERA (Europe) extent.
        let overlayBounds = response.imageBounds ?? response.bounds
        cacheLock.withLock {
            cachedFrameInfos[region] = response.frames
            cachedBounds[region] = overlayBounds
            lastFetchedTime[region] = Date()
        }
        return (response.frames, overlayBounds)
    }

    /// Raster path (today): server-colormapped image, decoded + flipped. Cached as a full
    /// RGBA CGImage in the shared 128 MB cache so re-opens/region switches skip the decode.
    private static func loadRasterImage(for frameInfo: OscarFrameInfo, region: RadarRegion) async -> CGImage? {
        let cacheKey = "\(region.pathComponent):\(frameInfo.key)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) { return cached }
        guard let image = await loadColormappedImage(for: frameInfo, region: region) else { return nil }
        imageCache.setObject(image, forKey: cacheKey, cost: image.width * image.height * 4)
        return image
    }

    private static func loadColormappedImage(for frameInfo: OscarFrameInfo, region: RadarRegion) async -> CGImage? {
        guard let url = URL(string: "\(baseURL)/radar/\(region.pathComponent)/frames/\(frameInfo.key)/image?cmap=plasma") else { return nil }
        do {
            var request = URLRequest(url: url)
            request.addAPIContactIdentity()
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let uiImage = UIImage(data: data) else { return nil }
            return prepareForRenderer(uiImage)
        } catch {
            return nil
        }
    }

    /// Grid path: download the raw 8-bit value grid and decode it to a compact index
    /// buffer. Colormapping to a full RGBA image is deferred to `OscarRadarFrame.cgImage`
    /// (only the on-screen frames), so the cached buffer stays ~4× smaller than an RGBA frame.
    private static func loadGridIndices(for frameInfo: OscarFrameInfo, region: RadarRegion) async -> (indices: [UInt8], width: Int, height: Int)? {
        guard let url = URL(string: "\(baseURL)/radar/\(region.pathComponent)/frames/\(frameInfo.key)/grid") else { return nil }
        do {
            var request = URLRequest(url: url)
            request.addAPIContactIdentity()
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let grid = UIImage(data: data)?.cgImage else { return nil }
            let w = grid.width, h = grid.height
            // Guard against a malformed/hostile grid causing an oversized allocation or w*h overflow.
            guard w > 0, h > 0, w <= 8192, h <= 8192 else { return nil }
            var indices = [UInt8](repeating: 0, count: w * h)
            let ok = indices.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                ctx.draw(grid, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
                return true
            }
            return ok ? (indices, w, h) : nil
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

    // MARK: - Value-grid colormap (client-side rendering path)

    // Resolves once (server-preferred, local fallback); every grid frame colormaps against it.
    private static var cachedPalette: [PixelRGBA]?

    /// The resolved 256-entry plasma palette (warming it on first call). Used by the off-main
    /// GPU materialization path; resolution is cheap (one cached network fetch, then memory).
    static func resolvedPalette() async -> [PixelRGBA] {
        await warmPalette()
        return cachedPalette ?? RadarPlasma.buildPalette()
    }

    /// Resolves the 256-entry plasma palette: server `/colormaps/plasma` preferred, local
    /// `RadarPlasma` fallback (kept in sync with the server) if it's unavailable.
    private static func warmPalette() async {
        if cachedPalette != nil { return }
        if let url = URL(string: "\(baseURL)/colormaps/plasma") {
            var request = URLRequest(url: url)
            request.addAPIContactIdentity()
            if let (data, _) = try? await URLSession.shared.data(for: request), data.count == 256 * 4 {
                cachedPalette = (0..<256).map {
                    let o = $0 * 4
                    return PixelRGBA(r: data[o], g: data[o + 1], b: data[o + 2], a: data[o + 3])
                }
                return
            }
        }
        if cachedPalette == nil { cachedPalette = RadarPlasma.buildPalette() }
    }

    /// Colormaps an 8-bit index buffer to a pre-flipped RGBA image (the renderer expects
    /// row 0 at the bottom), matching the raster path's CGImage shape.
    static func colormapIndices(_ indices: [UInt8], width w: Int, height h: Int) -> CGImage? {
        let palette = cachedPalette ?? RadarPlasma.buildPalette()
        var out = [UInt8](repeating: 0, count: w * h * 4)
        palette.withUnsafeBufferPointer { pal in
            indices.withUnsafeBufferPointer { g in
                out.withUnsafeMutableBufferPointer { o in
                    for y in 0..<h {
                        let srcRow = (h - 1 - y) * w
                        let dstRow = y * w * 4
                        for x in 0..<w {
                            let c = pal[Int(g[srcRow + x])]
                            let d = dstRow + x * 4
                            o[d] = c.r; o[d + 1] = c.g; o[d + 2] = c.b; o[d + 3] = c.a
                        }
                    }
                }
            }
        }
        guard let cf = CFDataCreate(nil, out, out.count),
              let provider = CGDataProvider(data: cf) else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    deinit {
        bootstrapTask?.cancel()
        focusedLoadTask?.cancel()
        backgroundPreloadTask?.cancel()
        playbackTimer?.invalidate()
    }
}

// MARK: - Value grid palette

struct PixelRGBA { let r: UInt8; let g: UInt8; let b: UInt8; let a: UInt8 }

/// Local fallback for the server `/colormaps/plasma` palette — kept in sync with
/// oscar-server's `Colormaps.plasma` so on-device rendering matches the raster path
/// when the palette endpoint is unreachable. idx 0 = transparent; sqrt-spaced.
private enum RadarPlasma {
    private struct Stop { let value: Double; let color: PixelRGBA }

    private static func colorHex(_ hex: String) -> PixelRGBA {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return PixelRGBA(r: UInt8((v >> 16) & 255), g: UInt8((v >> 8) & 255), b: UInt8(v & 255), a: 255)
    }
    private static func mmPer5(_ hourly: Double) -> Double { hourly / 12 }
    private static func dbzToMmH(_ dbz: Double) -> Double {
        let t: [(Double, Double)] = [(5, 0.07), (10, 0.15), (15, 0.3), (20, 0.6), (25, 1.3),
            (30, 2.7), (35, 5.6), (40, 11.53), (45, 23.7), (50, 48.6), (55, 100), (60, 205), (65, 421)]
        if dbz <= t[0].0 { return t[0].1 }
        for p in zip(t, t.dropFirst()) where dbz <= p.1.0 {
            return p.0.1 + (p.1.1 - p.0.1) * (dbz - p.0.0) / (p.1.0 - p.0.0)
        }
        let p = (t[t.count - 2], t[t.count - 1])
        return p.0.1 + (p.1.1 - p.0.1) * (dbz - p.0.0) / (p.1.0 - p.0.0)
    }
    private static let stops: [Stop] = {
        let bins: [(Double, String)] = [(1, "#99ffff"), (5.5, "#32ffff"), (10, "#00caca"),
            (14.5, "#009934"), (19, "#4cbf19"), (23.5, "#98cb03"), (28, "#cce603"), (32.5, "#ffff00"),
            (37, "#ffc400"), (41.5, "#ff8901"), (46, "#ff0000"), (50.5, "#b40000"), (55, "#4848ff"),
            (60, "#0000c9"), (65, "#990199"), (75, "#fe33ff")]
        return [Stop(value: 0, color: PixelRGBA(r: 0, g: 0, b: 0, a: 0))]
            + bins.map { Stop(value: mmPer5(dbzToMmH($0.0)), color: colorHex($0.1)) }
    }()
    private static let dbzMax = 85.0

    private static func sample(_ value: Double) -> PixelRGBA {
        guard let first = stops.first, let last = stops.last else { return PixelRGBA(r: 0, g: 0, b: 0, a: 0) }
        if value <= first.value { return first.color }
        if value >= last.value { return last.color }
        for p in zip(stops, stops.dropFirst()) where value >= p.0.value && value < p.1.value {
            let f = (value - p.0.value) / (p.1.value - p.0.value)
            func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
                UInt8(clamping: Int((Double(a) + f * (Double(b) - Double(a))).rounded()))
            }
            return PixelRGBA(r: mix(p.0.color.r, p.1.color.r), g: mix(p.0.color.g, p.1.color.g),
                             b: mix(p.0.color.b, p.1.color.b), a: mix(p.0.color.a, p.1.color.a))
        }
        return last.color
    }

    static func buildPalette() -> [PixelRGBA] {
        var pal = [PixelRGBA](repeating: PixelRGBA(r: 0, g: 0, b: 0, a: 0), count: 256)
        for i in 1..<256 {
            pal[i] = sample(mmPer5(dbzToMmH(Double(i) / 255 * dbzMax)))
        }
        return pal
    }
}

// MARK: - GPU value-grid colormapper

/// Ferries a CGImage out of a detached task. CGImage is an immutable, thread-safe
/// CoreGraphics object but isn't formally `Sendable`, so this box vouches for it.
private struct SendableCGImage: @unchecked Sendable { let image: CGImage? }

/// Maps an 8-bit value-grid index buffer + 256-entry RGBA palette to a drawable RGBA
/// `CGImage` on the GPU, off the main thread, via a runtime-compiled Metal compute shader
/// (a 1-D palette lookup per pixel). Falls back to a CPU loop when Metal is unavailable.
/// Output is vertically flipped (row 0 at the bottom) to match the MapKit overlay renderer,
/// exactly like the raster path's `prepareForRenderer`, and uses straight RGBA under
/// `premultipliedLast` — valid because the plasma palette's alpha is only ever 0 (index 0,
/// rgb=0) or 255, so premultiplied equals straight.
enum RadarGridColormapper {
    private struct GPU {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLComputePipelineState
    }

    // Built once. nil if the device lacks Metal or the shader fails to compile → CPU path.
    private static let gpu: GPU? = makeGPU()

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void radar_colormap(
        device const uchar*  indices [[buffer(0)]],
        device const uchar4* palette [[buffer(1)]],
        device uchar4*       out     [[buffer(2)]],
        constant uint2&      dims    [[buffer(3)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= dims.x || gid.y >= dims.y) { return; }
        uint srcRow = (dims.y - 1 - gid.y) * dims.x;   // vertical flip for MapKit
        uint dst    = gid.y * dims.x + gid.x;
        out[dst] = palette[indices[srcRow + gid.x]];
    }
    """

    private static func makeGPU() -> GPU? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let function = library.makeFunction(name: "radar_colormap"),
              let pipeline = try? device.makeComputePipelineState(function: function) else { return nil }
        return GPU(device: device, queue: queue, pipeline: pipeline)
    }

    /// Colormap off the main thread (GPU, CPU fallback). Returns a pre-flipped RGBA image
    /// matching the raster path's CGImage shape.
    static func makeImage(indices: [UInt8], width: Int, height: Int, palette: [PixelRGBA]) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            SendableCGImage(image: render(indices: indices, width: width, height: height, palette: palette))
        }.value.image
    }

    private static func render(indices: [UInt8], width w: Int, height h: Int, palette: [PixelRGBA]) -> CGImage? {
        guard w > 0, h > 0, indices.count >= w * h, palette.count >= 256 else { return nil }
        if let image = gpuRender(indices: indices, width: w, height: h, palette: palette) { return image }
        return cpuRender(indices: indices, width: w, height: h, palette: palette)
    }

    private static func gpuRender(indices: [UInt8], width w: Int, height h: Int, palette: [PixelRGBA]) -> CGImage? {
        guard let gpu else { return nil }
        let device = gpu.device
        let pixels = w * h
        var paletteBytes = [UInt8](repeating: 0, count: 256 * 4)
        for i in 0..<256 {
            let p = palette[i], o = i * 4
            paletteBytes[o] = p.r; paletteBytes[o + 1] = p.g; paletteBytes[o + 2] = p.b; paletteBytes[o + 3] = p.a
        }
        var dims = SIMD2<UInt32>(UInt32(w), UInt32(h))

        guard let inBuf = device.makeBuffer(bytes: indices, length: pixels, options: .storageModeShared),
              let palBuf = device.makeBuffer(bytes: paletteBytes, length: paletteBytes.count, options: .storageModeShared),
              let outBuf = device.makeBuffer(length: pixels * 4, options: .storageModeShared),
              let command = gpu.queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else { return nil }

        encoder.setComputePipelineState(gpu.pipeline)
        encoder.setBuffer(inBuf, offset: 0, index: 0)
        encoder.setBuffer(palBuf, offset: 0, index: 1)
        encoder.setBuffer(outBuf, offset: 0, index: 2)
        encoder.setBytes(&dims, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 3)
        let group = MTLSize(width: 16, height: 16, depth: 1)
        let grid = MTLSize(width: (w + 15) / 16, height: (h + 15) / 16, depth: 1)
        encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: group)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return nil }

        // storageModeShared → CPU-visible after completion; copy into CFData the CGImage owns.
        let rgba = Data(bytes: outBuf.contents(), count: pixels * 4)
        return makeCGImage(rgba: rgba, width: w, height: h)
    }

    private static func cpuRender(indices: [UInt8], width w: Int, height h: Int, palette: [PixelRGBA]) -> CGImage? {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        palette.withUnsafeBufferPointer { pal in
            indices.withUnsafeBufferPointer { g in
                out.withUnsafeMutableBufferPointer { o in
                    for y in 0..<h {
                        let srcRow = (h - 1 - y) * w
                        let dstRow = y * w * 4
                        for x in 0..<w {
                            let c = pal[Int(g[srcRow + x])]
                            let d = dstRow + x * 4
                            o[d] = c.r; o[d + 1] = c.g; o[d + 2] = c.b; o[d + 3] = c.a
                        }
                    }
                }
            }
        }
        return makeCGImage(rgba: Data(out), width: w, height: h)
    }

    private static func makeCGImage(rgba: Data, width w: Int, height h: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: rgba as CFData) else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

// MARK: - API Models

private struct OscarFramesResponse: Decodable {
    let frames: [OscarFrameInfo]
    let bounds: OscarBoundsInfo
    let imageBounds: OscarBoundsInfo?

    enum CodingKeys: String, CodingKey {
        case frames
        case bounds
        case imageBounds = "image_bounds"
    }
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

    /// Which oscar-server radar coverage the user selected for the map. Backed by
    /// `oscarRadarRegionRaw`; defaults to Germany (DWD).
    var oscarRadarRegion: RadarRegion {
        get { RadarRegion(rawValue: oscarRadarRegionRaw) ?? .germany }
        set { oscarRadarRegionRaw = newValue.rawValue }
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
        case .iconPrecip, .iconTemp, .iconWind: return "models/icon/frames"
        case .gfsPrecip, .gfsTemp, .gfsWind:   return "models/gfs/frames"
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

    /// Frames-path prefix for full-world image requests. Combined with the frame
    /// key and variable: `{imagePath}/{frameKey}/{variableSegment}/image`.
    var imagePath: String? { framesEndpoint }

    /// Variable path segment in oscar-server model URLs.
    var variableSegment: String {
        switch self {
        case .iconPrecip, .gfsPrecip: return "precipitation"
        case .iconTemp, .gfsTemp:     return "temperature"
        case .iconWind, .gfsWind:     return "wind"
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
    private(set) var isMapInteracting = false

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundPreloadTask: Task<Void, Never>?
    @ObservationIgnored private var focusedLoadTask: Task<Void, Never>?
    @ObservationIgnored private var playbackTimer: Timer?
    @ObservationIgnored private var frameInfos: [TileFrameInfo] = []
    @ObservationIgnored private var frameDates: [Date?] = []
    @ObservationIgnored private var loadSessionID = UUID()
    @ObservationIgnored private var suppressSelectionSideEffects = false
    @ObservationIgnored private let renderMode: MapRenderMode

    // Shared across instances — survives layer switches.
    private static let imageCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()

    static func purgeDecodedCaches() {
        imageCache.removeAllObjects()
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
        frameDates = []
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
                let dates = timestamps.map(parseFrameDate)
                let keys = fetchedFrameInfos.map(\.key)
                let closest = closestTimestampIndex(in: dates)

                self.suppressSelectionSideEffects = true
                self.frameInfos = fetchedFrameInfos
                self.frames = Array(repeating: nil, count: fetchedFrameInfos.count)
                self.frameTimestamps = timestamps
                self.frameDates = dates
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
              !isMapInteracting,
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

        let cached = Self.imageCache.object(forKey: cacheKey as NSString)

        let cgImage: CGImage?
        if let cached {
            cgImage = cached
        } else {
            guard !Task.isCancelled,
                  let url = URL(string: "\(Self.baseURL)/\(imagePath)/\(info.key)/\(layer.variableSegment)/image") else {
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
            Self.imageCache.setObject(
                decoded,
                forKey: cacheKey as NSString,
                cost: decoded.width * decoded.height * 4
            )
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
