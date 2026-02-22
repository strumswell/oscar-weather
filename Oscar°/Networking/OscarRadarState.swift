import Foundation
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

    // MARK: - Private Helpers

    /// Index in `timestamps` whose value is closest to the current time.
    private func closestIndex(in timestamps: [String]) -> Int {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        var best = 0, bestDiff = TimeInterval.infinity
        for (i, ts) in timestamps.enumerated() {
            if let date = formatter.date(from: ts) {
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
        if isCacheValid, let bounds = cachedBounds, !cachedFrameInfos.isEmpty {
            return (cachedFrameInfos, bounds)
        }
        cachedImages.removeAll()
        guard let url = URL(string: "\(baseURL)/radar/frames") else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(OscarFramesResponse.self, from: data)
        cachedFrameInfos = response.frames
        cachedBounds = response.bounds
        lastFetchedTime = Date()
        return (response.frames, response.bounds)
    }

    /// Returns a cached CGImage for the frame, or downloads and caches it if missing.
    private static func loadImage(for frameInfo: OscarFrameInfo) async -> CGImage? {
        if let cached = cachedImages[frameInfo.key] { return cached }
        guard let url = URL(string: "\(baseURL)/radar/image/\(frameInfo.key).webp?cmap=plasma") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data), let cgImage = prepareForRenderer(uiImage) else { return nil }
            cachedImages[frameInfo.key] = cgImage
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
