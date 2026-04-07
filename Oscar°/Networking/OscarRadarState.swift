import Foundation
import MapKit
import UIKit

struct OscarRadarBounds {
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

@Observable
class OscarRadarState {
    // nil slots represent frames whose image hasn't arrived yet.
    // The array is pre-sized to the full frame count as soon as metadata loads.
    var frames: [OscarRadarFrame?] = []

    // Populated from metadata immediately — lets us show the scrubber skeleton
    // and compute the live-frame index before any images have downloaded.
    private(set) var frameTimestamps: [String] = []

    var bounds: OscarRadarBounds?
    var isLoading: Bool = false
    var currentFrameIndex: Int = 0
    var isPlaying: Bool = false
    var error: String?

    private var playbackTimer: Timer?
    private static let baseURL = "https://radar.oscars.love"
    private static let cacheLock = NSLock()

    // MARK: - Derived state

    var currentFrame: OscarRadarFrame? {
        guard currentFrameIndex < frames.count else { return nil }
        return frames[currentFrameIndex]
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
        return currentFrameIndex == closestIndex(in: frameTimestamps)
    }

    var hasAnyLoadedFrame: Bool {
        frames.contains { $0 != nil }
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

    // MARK: - Loading

    /// Loads only the frame closest to the current time.
    /// Designed for NowView: fast, minimal network work.
    func loadCurrentFrame() async {
        guard !isLoading else { return }
        await MainActor.run { isLoading = true; error = nil }

        do {
            let (frameInfos, boundsInfo) = try await Self.fetchFrameInfos()
            guard !frameInfos.isEmpty else {
                await MainActor.run { isLoading = false }
                return
            }

            let timestamps = frameInfos.map { $0.timestamp }
            let closest = closestIndex(in: timestamps)

            // Pre-size the frames array so the scrubber skeleton has the right slot count
            // even though we're only loading one image.
            await MainActor.run {
                self.bounds = boundsInfo.asDomain
                self.frameTimestamps = timestamps
                if self.frames.count != frameInfos.count {
                    self.frames = Array(repeating: nil, count: frameInfos.count)
                }
                self.currentFrameIndex = closest
                self.isLoading = false
            }

            guard let cgImage = await Self.loadImage(for: frameInfos[closest]) else { return }
            let frame = OscarRadarFrame(
                key: frameInfos[closest].key,
                timestamp: frameInfos[closest].timestamp,
                cgImage: cgImage
            )

            await MainActor.run {
                var updated = self.frames
                updated[closest] = frame
                self.frames = updated
            }
        } catch {
            await MainActor.run {
                self.error = "Fehler beim Laden: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    /// Loads all frames, showing the scrubber skeleton immediately after metadata
    /// arrives and filling in ticks progressively as each image downloads.
    func loadAllFrames() async {
        guard !isLoading else { return }
        await MainActor.run { isLoading = true; error = nil }

        do {
            let (frameInfos, boundsInfo) = try await Self.fetchFrameInfos()
            guard !frameInfos.isEmpty else {
                await MainActor.run { isLoading = false }
                return
            }

            let timestamps = frameInfos.map { $0.timestamp }
            let closest = closestIndex(in: timestamps)

            // Phase 1: show the skeleton scrubber immediately.
            await MainActor.run {
                self.bounds = boundsInfo.asDomain
                self.frameTimestamps = timestamps
                if self.frames.count != frameInfos.count {
                    self.frames = Array(repeating: nil, count: frameInfos.count)
                }
                self.currentFrameIndex = closest
                self.isLoading = false  // skeleton is ready — hide the loading chip
            }

            // Phase 2: download images in parallel, filling ticks as they arrive.
            await withTaskGroup(of: (Int, OscarRadarFrame?).self) { group in
                for (index, frameInfo) in frameInfos.enumerated() {
                    group.addTask {
                        guard let cgImage = await Self.loadImage(for: frameInfo) else {
                            return (index, nil)
                        }
                        return (index, OscarRadarFrame(
                            key: frameInfo.key,
                            timestamp: frameInfo.timestamp,
                            cgImage: cgImage
                        ))
                    }
                }

                for await (index, frame) in group {
                    await MainActor.run {
                        var updated = self.frames
                        updated[index] = frame
                        self.frames = updated
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.error = "Fehler beim Laden: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    // MARK: - Playback

    @MainActor
    func play() {
        guard hasAnyLoadedFrame else { return }
        isPlaying = true
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, !self.frames.isEmpty else { return }
            // Advance, skipping over nil (not-yet-loaded) slots.
            var next = (self.currentFrameIndex + 1) % self.frames.count
            var checked = 0
            while self.frames[next] == nil && checked < self.frames.count {
                next = (next + 1) % self.frames.count
                checked += 1
            }
            self.currentFrameIndex = next
        }
    }

    @MainActor
    func pause() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    /// Stops the internal Timer without changing `isPlaying`.
    /// Called when the Metal display link takes over frame advancement.
    @MainActor
    func cancelInternalTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    /// Advance to the next loaded frame. Called by the Metal display-link tick.
    @MainActor
    func advanceFrame() {
        guard !frames.isEmpty else { return }
        var next = (currentFrameIndex + 1) % frames.count
        var checked = 0
        while frames[next] == nil && checked < frames.count {
            next = (next + 1) % frames.count
            checked += 1
        }
        currentFrameIndex = next
    }

    // MARK: - Private Helpers

    /// Index in `timestamps` whose value is closest to the current time.
    private func closestIndex(in timestamps: [String]) -> Int {
        let now = Date()
        // Two local formatters (ISO8601DateFormatter is not thread-safe — avoid shared statics here).
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let fmtFrac = ISO8601DateFormatter()
        fmtFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var best = 0, bestDiff = TimeInterval.infinity
        for (i, ts) in timestamps.enumerated() {
            let date = fmtFrac.date(from: ts)
                ?? fmt.date(from: ts)
                ?? Double(ts).map { Date(timeIntervalSince1970: $0) }
            if let date {
                let diff = abs(now.timeIntervalSince(date))
                if diff < bestDiff { bestDiff = diff; best = i }
            }
        }
        return best
    }

    private func findClosestFrameToCurrentTime() -> Int {
        closestIndex(in: frameTimestamps)
    }

    /// Fetches frame metadata from the server, or returns the cached list if still valid.
    /// Clears the image cache when the metadata expires, since frame keys will have changed.
    private static func fetchFrameInfos() async throws -> ([OscarFrameInfo], OscarBoundsInfo) {
        cacheLock.lock()
        if isCacheValid, let bounds = cachedBounds, !cachedFrameInfos.isEmpty {
            let frames = cachedFrameInfos
            cacheLock.unlock()
            return (frames, bounds)
        }
        cachedImages.removeAll()
        cacheLock.unlock()

        guard let url = URL(string: "\(baseURL)/radar/frames") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.addAPIContactIdentity()
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OscarFramesResponse.self, from: data)
        cacheLock.lock()
        cachedFrameInfos = response.frames
        cachedBounds = response.bounds
        lastFetchedTime = Date()
        cacheLock.unlock()
        return (response.frames, response.bounds)
    }

    /// Returns a cached CGImage for the frame, or downloads and caches it if missing.
    private static func loadImage(for frameInfo: OscarFrameInfo) async -> CGImage? {
        cacheLock.lock()
        if let cached = cachedImages[frameInfo.key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let url = URL(string: "\(baseURL)/radar/image/\(frameInfo.key).webp?cmap=plasma") else { return nil }
        do {
            var request = URLRequest(url: url)
            request.addAPIContactIdentity()
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let uiImage = UIImage(data: data) else { return nil }
            guard let cgImage = prepareForRenderer(uiImage) else { return nil }
            cacheLock.lock()
            cachedImages[frameInfo.key] = cgImage
            cacheLock.unlock()
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
    private static func prepareForRenderer(_ image: UIImage) -> CGImage? {
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

    var sourceLabel: String {
        switch self {
        case .iconPrecip, .iconTemp, .iconWind: return "DWD ICON-D2"
        case .gfsPrecip, .gfsTemp, .gfsWind:   return "NOAA GFS"
        }
    }

    /// Domain bounds (west, east, north, south) used for tile pre-fetching.
    var preloadBounds: (west: Double, east: Double, north: Double, south: Double) {
        switch self {
        case .iconPrecip, .iconTemp, .iconWind:
            return (west: -2, east: 22, north: 56, south: 43)
        case .gfsPrecip, .gfsTemp, .gfsWind:
            return (west: -5, east: 25, north: 60, south: 42)
        }
    }
}

// MARK: WeatherTileFrame

struct WeatherTileFrame: Identifiable {
    let id = UUID()
    let key: String
    let validTime: String
}

private actor WeatherTileMetadataCache {
    private var cachedFrames: [String: [WeatherTileFrame]] = [:]
    private var lastFetchTime: [String: Date] = [:]
    private let cacheDuration: TimeInterval = 60 * 60 // 1 h

    func frames(for endpoint: String, forceRefresh: Bool) -> [WeatherTileFrame]? {
        guard !forceRefresh,
              let last = lastFetchTime[endpoint],
              Date().timeIntervalSince(last) < cacheDuration,
              let cached = cachedFrames[endpoint],
              !cached.isEmpty else {
            return nil
        }
        return cached
    }

    func store(_ frames: [WeatherTileFrame], for endpoint: String) {
        cachedFrames[endpoint] = frames
        lastFetchTime[endpoint] = Date()
    }
}

// MARK: WeatherTileState

@Observable
final class WeatherTileState {
    static let baseURL = "https://radar.oscars.love"

    private(set) var frames: [WeatherTileFrame] = []
    var currentFrameIndex: Int = 0
    var isPlaying: Bool = false
    var isLoading: Bool = false
    var error: String?
    private(set) var currentLayer: WeatherTileLayer = .iconPrecip

    private var playbackTimer: Timer?
    private var preloadTask: Task<Void, Never>?
    private var visiblePrefetchTask: Task<Void, Never>?

    private static let metadataCache = WeatherTileMetadataCache()

    // MARK: - Derived

    var frameTimestamps: [String] { frames.map { $0.validTime } }

    var currentFrameKey: String? {
        guard !frames.isEmpty, currentFrameIndex < frames.count else { return nil }
        return frames[currentFrameIndex].key
    }

    var currentFrameTimestamp: String? {
        guard !frames.isEmpty, currentFrameIndex < frames.count else { return nil }
        return frames[currentFrameIndex].validTime
    }

    var isCurrentFrameLive: Bool {
        guard !frames.isEmpty else { return false }
        return currentFrameIndex == closestIndex(in: frameTimestamps)
    }

    // MARK: - Load

    func switchLayer(_ layer: WeatherTileLayer) async {
        let changed = layer != currentLayer
        await MainActor.run { currentLayer = layer }
        await loadFrames(forceRefresh: changed)
    }

    func loadFrames(forceRefresh: Bool = false) async {
        let layer = currentLayer
        await MainActor.run { isLoading = true; error = nil }

        do {
            let newFrames = try await Self.fetchFrames(
                endpoint: layer.framesEndpoint, forceRefresh: forceRefresh)
            guard !newFrames.isEmpty else {
                await MainActor.run { isLoading = false }
                return
            }

            let closest = closestIndex(in: newFrames.map { $0.validTime })

            await MainActor.run {
                guard self.currentLayer == layer else { return }
                self.frames = newFrames
                self.currentFrameIndex = closest
                self.isLoading = false
            }

            preloadTask?.cancel()
            preloadTask = nil
        } catch {
            await MainActor.run {
                self.error = "Fehler: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    // MARK: - Playback

    @MainActor
    func play() {
        guard !frames.isEmpty else { return }
        isPlaying = true
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.advanceFrame()
        }
    }

    @MainActor
    func pause() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    @MainActor
    func advanceFrame() {
        guard !frames.isEmpty else { return }
        currentFrameIndex = (currentFrameIndex + 1) % frames.count
    }

    // MARK: - Tile URL Template

    func tileURLTemplate() -> String? {
        guard let key = currentFrameKey else { return nil }
        return "\(Self.baseURL)/\(currentLayer.tilePath)/\(key)/{z}/{x}/{y}.webp"
    }

    // MARK: - Preloading

    func prefetchVisibleTiles(
        around frameIndex: Int,
        visibleMapRect: MKMapRect,
        zoomScale: MKZoomScale,
        layer explicitLayer: WeatherTileLayer? = nil,
        radius: Int = 2
    ) {
        guard !frames.isEmpty, frames.indices.contains(frameIndex) else { return }

        visiblePrefetchTask?.cancel()
        let layer = explicitLayer ?? currentLayer
        let nearbyFrames = frames[
            max(0, frameIndex - radius)...min(frames.count - 1, frameIndex + radius)
        ].map { $0 }
        let zoom = tileZoom(zoomScale: zoomScale)
        let bounds = Self.coordinateBounds(for: visibleMapRect)
        let urls = tileURLs(frames: nearbyFrames, path: layer.tilePath, bounds: bounds, zooms: [zoom])

        visiblePrefetchTask = Task.detached(priority: .utility) { [weak self] in
            await self?.fetchIntoCache(urls: urls, concurrency: 4)
        }
    }

    func prepareVisibleTiles(
        for frameIndex: Int,
        layer: WeatherTileLayer,
        visibleMapRect: MKMapRect,
        zoomScale: MKZoomScale
    ) async {
        guard !frames.isEmpty, frames.indices.contains(frameIndex) else { return }

        let zoom = tileZoom(zoomScale: zoomScale)
        let bounds = Self.coordinateBounds(for: visibleMapRect)
        let urls = tileURLs(
            frames: [frames[frameIndex]],
            path: layer.tilePath,
            bounds: bounds,
            zooms: [zoom]
        )
        await fetchIntoCache(urls: urls, concurrency: 8)
    }

    private func tileURLs(
        frames: [WeatherTileFrame],
        path: String,
        bounds: (west: Double, east: Double, north: Double, south: Double),
        zooms: [Int]
    ) -> [URL] {
        var result: [URL] = []
        for z in zooms {
            let maxTile = Int(pow(2, Double(z))) - 1
            let x0 = max(0, min(maxTile, tileX(bounds.west, zoom: z)))
            let x1 = max(0, min(maxTile, tileX(bounds.east, zoom: z)))
            let y0 = max(0, min(maxTile, tileY(bounds.north, zoom: z)))
            let y1 = max(0, min(maxTile, tileY(bounds.south, zoom: z)))
            for frame in frames {
                for x in min(x0, x1)...max(x0, x1) {
                    for y in min(y0, y1)...max(y0, y1) {
                        let s = "\(Self.baseURL)/\(path)/\(frame.key)/\(z)/\(x)/\(y).webp"
                        if let url = URL(string: s) { result.append(url) }
                    }
                }
            }
        }
        return result
    }

    private func fetchIntoCache(urls: [URL], concurrency: Int) async {
        let pending = urls.filter {
            var request = URLRequest(url: $0)
            request.addAPIContactIdentity()
            return URLCache.shared.cachedResponse(for: request) == nil
        }
        guard !pending.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            for url in pending {
                guard !Task.isCancelled else { break }
                if inFlight >= concurrency {
                    await group.next()
                    inFlight -= 1
                }
                group.addTask {
                    var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                    req.addAPIContactIdentity()
                    guard let (data, response) = try? await URLSession.shared.data(for: req),
                          let http = response as? HTTPURLResponse,
                          http.statusCode == 200, !data.isEmpty else { return }
                    let cached = CachedURLResponse(response: response, data: data)
                    URLCache.shared.storeCachedResponse(cached, for: req)
                }
                inFlight += 1
            }
        }
    }

    // MARK: - Fetch

    private static func fetchFrames(endpoint: String, forceRefresh: Bool) async throws -> [WeatherTileFrame] {
        if let cached = await metadataCache.frames(for: endpoint, forceRefresh: forceRefresh) {
            return cached
        }
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else { throw URLError(.badURL) }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.addAPIContactIdentity()
        let (data, _) = try await URLSession.shared.data(for: req)
        let decoded = try JSONDecoder().decode(TileFramesResponse.self, from: data)
        let result = decoded.frames.map { WeatherTileFrame(key: $0.key, validTime: $0.validTime) }
        await metadataCache.store(result, for: endpoint)
        return result
    }

    // MARK: - Helpers

    private func closestIndex(in timestamps: [String]) -> Int {
        let now = Date()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let fmtFrac = ISO8601DateFormatter()
        fmtFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var best = 0, bestDiff = TimeInterval.infinity
        for (i, ts) in timestamps.enumerated() {
            guard let date = fmtFrac.date(from: ts) ?? fmt.date(from: ts) else { continue }
            let diff = abs(now.timeIntervalSince(date))
            if diff < bestDiff { bestDiff = diff; best = i }
        }
        return best
    }

    private func tileX(_ lon: Double, zoom: Int) -> Int {
        Int(floor((lon + 180) / 360 * pow(2, Double(zoom))))
    }

    private func tileY(_ lat: Double, zoom: Int) -> Int {
        let rad = lat * .pi / 180
        return Int(floor((1 - log(tan(rad) + 1 / cos(rad)) / .pi) / 2 * pow(2, Double(zoom))))
    }

    private func tileZoom(zoomScale: MKZoomScale) -> Int {
        let numTilesAt1_0 = MKMapSize.world.width / 256.0
        let zoomLevelAt1_0 = log2(numTilesAt1_0)
        return max(0, Int(zoomLevelAt1_0 + floor(log2(Double(zoomScale)) + 0.5)))
    }

    private static func coordinateBounds(
        for mapRect: MKMapRect
    ) -> (west: Double, east: Double, north: Double, south: Double) {
        let topLeft = MKMapPoint(x: mapRect.minX, y: mapRect.minY).coordinate
        let bottomRight = MKMapPoint(x: mapRect.maxX, y: mapRect.maxY).coordinate
        return (
            west: min(topLeft.longitude, bottomRight.longitude),
            east: max(topLeft.longitude, bottomRight.longitude),
            north: max(topLeft.latitude, bottomRight.latitude),
            south: min(topLeft.latitude, bottomRight.latitude)
        )
    }

    deinit {
        playbackTimer?.invalidate()
        preloadTask?.cancel()
        visiblePrefetchTask?.cancel()
    }
}

// MARK: - API Models (tile layers)

private struct TileFramesResponse: Decodable {
    let frames: [TileFrameInfo]
}

private struct TileFrameInfo: Decodable {
    let key: String
    let validTime: String
}
