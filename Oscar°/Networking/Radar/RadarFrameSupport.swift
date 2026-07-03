//
//  RadarFrameSupport.swift
//  Oscar°
//
//  Shared building blocks of the radar and model grid states: frame/grid
//  payload types, the serial decode lane, cache budgeting, and the
//  timeline-index helpers.
//

import Foundation
import UIKit
import os

struct PixelRGBA { let r: UInt8; let g: UInt8; let b: UInt8; let a: UInt8 }

/// One radar timeline frame: the server's 8-bit value grid (quantized dBZ indices),
/// colormapped on the GPU at draw time by the MapLibre custom layer. Row 0 = north.
@MainActor
final class OscarRadarFrame: Identifiable {
    let id = UUID()
    let key: String
    let timestamp: String
    let gridPayload: RadarGridPayload

    init(key: String, timestamp: String, gridIndices: [UInt8], width: Int, height: Int) {
        self.key = key
        self.timestamp = timestamp
        self.gridPayload = RadarGridPayload(indices: gridIndices, width: width, height: height)
    }
}

/// A frame's raw 8-bit value grid (index into a 256-entry palette; row 0 = north).
struct RadarGridPayload: Sendable {
    let indices: [UInt8]
    let width: Int
    let height: Int
}

/// Reference wrapper so grid payloads can live in an `NSCache`.
final class GridPayloadBox: Sendable {
    let payload: RadarGridPayload
    init(payload: RadarGridPayload) { self.payload = payload }
}

/// Serial decode lane: ALL CPU-heavy frame decoding (WebP → grid extraction) funnels
/// through this one actor, one frame at a time, off the main thread.
/// Two constraints meet here: (1) fully parallel decode was shipped once and reverted —
/// concurrent full-composite decodes saturate the CPU and overheat the device; downloads
/// may overlap freely, decode must not. (2) The old inline decode ran on the main actor
/// (the class is @MainActor), so every frame decode blocked the UI — this moves it off.
actor RadarFrameDecodeLane {
    static let shared = RadarFrameDecodeLane()

    /// Decode the lossless WebP and extract the 8-bit index plane.
    func decodeGrid(_ data: Data) -> RadarGridPayload? {
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
        return ok ? RadarGridPayload(indices: indices, width: w, height: h) : nil
    }
}

/// Cache budget derived from the process's actual memory headroom (`os_proc_available_memory`,
/// sampled at startup) instead of a fixed constant — a 6–8 GB device can afford to keep the
/// whole timeline warm; a 3 GB one cannot.
func adaptiveCacheBudget(fraction: Double, floor floorBytes: Int, cap: Int) -> Int {
    let available = Int(clamping: os_proc_available_memory())
    guard available > 0 else { return floorBytes }
    return min(cap, max(floorBytes, Int(Double(available) * fraction)))
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
    nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

func parseFrameDate(_ timestamp: String) -> Date? {
    FrameDateParser.fractional.date(from: timestamp)
        ?? FrameDateParser.plain.date(from: timestamp)
        ?? Double(timestamp).map { Date(timeIntervalSince1970: $0) }
}

func closestTimestampIndex(in dates: [Date?]) -> Int {
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

func prioritizedFrameIndices(count: Int, around center: Int) -> [Int] {
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

func nextLoadedIndex(in loaded: [Bool], after index: Int) -> Int? {
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

func contiguousLoadedRange(in loaded: [Bool], around anchor: Int?) -> ClosedRange<Int>? {
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

func allowsBackgroundPreload(for renderMode: MapRenderMode) -> Bool {
    guard renderMode.allowsBackgroundPreload else { return false }

    switch ProcessInfo.processInfo.thermalState {
    case .serious, .critical:
        return false
    default:
        return true
    }
}
