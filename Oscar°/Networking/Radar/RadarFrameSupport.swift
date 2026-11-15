//
//  RadarFrameSupport.swift
//  Oscar°
//
//  Shared building blocks of the radar and model grid states: frame/grid
//  payload types, the serial decode lane, cache budgeting, and the
//  timeline-index helpers.
//

import Compression
import Foundation
import UIKit
import os

struct PixelRGBA { let r: UInt8; let g: UInt8; let b: UInt8; let a: UInt8 }

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

struct RadarGridPayload: Sendable {
    let indices: [UInt8]
    let width: Int
    let height: Int
}

final class GridPayloadBox: Sendable {
    let payload: RadarGridPayload
    init(payload: RadarGridPayload) { self.payload = payload }
}

actor RadarFrameDecodeLane {
    static let shared = RadarFrameDecodeLane()

    func decodeGrid(_ data: Data) -> RadarGridPayload? {
        guard let grid = UIImage(data: data)?.cgImage else { return nil }
        let w = grid.width, h = grid.height
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

    func decodeRawGrid(_ data: Data) -> RadarGridPayload? {
        guard data.count > 8 else { return nil }
        let (width, height) = data.withUnsafeBytes { raw in
            (Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 0, as: UInt32.self))),
             Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self))))
        }
        guard width > 0, height > 0, width <= 8192, height <= 8192 else { return nil }
        let count = width * height
        var indices = [UInt8](repeating: 0, count: count)
        let written = data.withUnsafeBytes { raw in
            compression_decode_buffer(&indices, count,
                                      raw.baseAddress!.advanced(by: 8).assumingMemoryBound(to: UInt8.self),
                                      raw.count - 8, nil, COMPRESSION_ZLIB)
        }
        return written == count ? RadarGridPayload(indices: indices, width: width, height: height) : nil
    }
}

func adaptiveCacheBudget(fraction: Double, floor floorBytes: Int, cap: Int) -> Int {
    let available = Int(clamping: os_proc_available_memory())
    guard available > 0 else { return floorBytes }
    return min(cap, max(floorBytes, Int(Double(available) * fraction)))
}

func residencyWindow(count: Int, center: Int, bytesPerFrame: Int, budget: Int) -> Set<Int> {
    let radius = max(8, budget / max(1, bytesPerFrame) / 2)
    guard count > 2 * radius + 1 else { return Set(0..<count) }
    return Set((center - radius...center + radius).map { (($0 % count) + count) % count })
}

func parseFrameDate(_ timestamp: String) -> Date? {
    PrecipSeriesDate.parse(timestamp)
}

func closestTimestampIndex(in dates: [Date?]) -> Int {
    let now = Date()
    let diffs = dates.map { $0.map { abs(now.timeIntervalSince($0)) } ?? .infinity }
    return diffs.indices.min { diffs[$0] < diffs[$1] } ?? 0
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

func nearestLoadedIndex(in loaded: [Bool], around center: Int) -> Int? {
    prioritizedFrameIndices(count: loaded.count, around: center).first { loaded[$0] }
}

func loadsToStart(count: Int, center: Int, inFlight: Int, limit: Int,
                  isCandidate: (Int) -> Bool) -> [Int] {
    let order = prioritizedFrameIndices(count: count, around: center).filter(isCandidate)
    let picks = Array(order.prefix(max(0, limit - inFlight)))
    if picks.isEmpty, inFlight < 2 * limit, let first = order.first, first == center { return [first] }
    return picks
}

func frameLoadLimit() -> Int {
    ProcessInfo.processInfo.thermalState == .nominal ? 4 : 1
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

func allowsBackgroundPreload() -> Bool {
    switch ProcessInfo.processInfo.thermalState {
    case .serious, .critical:
        return false
    default:
        return true
    }
}
