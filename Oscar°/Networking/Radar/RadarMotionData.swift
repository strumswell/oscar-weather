//
//  RadarMotionData.swift
//  Oscar°
//
//  Decoded /radar/{region}/motion payload: per-pair flow fields for the
//  morph rendering and the motion arrows.
//

import Foundation

// MARK: - Motion fields (/radar/{region}/motion)

/// Decoded `/radar/{region}/motion` payload: per adjacent served frame pair, a coarse
/// flow field in OVERVIEW-IMAGE pixels per server step (5 min), quantized Int16 ×
/// `scale` on the wire. The morph shader samples it as an rg32Float texture and warps
/// the two frame textures toward each other (two-sided backward warp).
struct RadarMotionData: Sendable {
    struct Pair: Sendable {
        let fieldIndex: Int
        let gapMinutes: Int
    }

    /// Identity token so consumers (the layer's flow-texture cache) can cheaply tell
    /// "same payload" from "new payload" without comparing the field arrays.
    let id = UUID()
    let cols: Int
    let rows: Int
    let overviewWidth: Int
    let overviewHeight: Int
    let stepMinutes: Int
    /// Per field: `cols·rows` u values then `cols·rows` v values (row-major each),
    /// in overview px per step. +u = east, +v = south (matches texture row order).
    let fields: [[Float]]
    /// Keyed `"fromKey|toKey"` for adjacent served frames, in timeline order.
    let pairs: [String: Pair]
    /// Fallback keyed by the pair's FROM frame: when the displayed pair skips served
    /// frames (progressive loading), the from-frame's field still describes the local
    /// flow — the caller rescales it by the actual timestamp gap.
    let pairsByFrom: [String: Pair]

    init?(jsonData: Data) {
        struct Payload: Decodable {
            struct PairDTO: Decodable {
                let from: String
                let to: String
                let field: Int
                let gap_minutes: Int
            }
            let cols: Int
            let rows: Int
            let overview_width: Int
            let overview_height: Int
            let scale: Double
            let step_minutes: Int
            let fields: [String]
            let pairs: [PairDTO]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: jsonData),
              payload.cols > 1, payload.rows > 1,
              payload.overview_width > 0, payload.overview_height > 0 else { return nil }
        let count = payload.cols * payload.rows
        var decodedFields: [[Float]] = []
        decodedFields.reserveCapacity(payload.fields.count)
        for encoded in payload.fields {
            guard let raw = Data(base64Encoded: encoded), raw.count == count * 2 * 2 else { return nil }
            let scale = Float(payload.scale)
            let values = raw.withUnsafeBytes { bytes -> [Float] in
                let int16 = bytes.bindMemory(to: Int16.self)
                return (0..<count * 2).map { Float(Int16(littleEndian: int16[$0])) * scale }
            }
            decodedFields.append(values)
        }
        var pairMap: [String: Pair] = [:]
        var fromMap: [String: Pair] = [:]
        for pair in payload.pairs where decodedFields.indices.contains(pair.field) {
            let decoded = Pair(fieldIndex: pair.field, gapMinutes: pair.gap_minutes)
            pairMap["\(pair.from)|\(pair.to)"] = decoded
            if fromMap[pair.from] == nil { fromMap[pair.from] = decoded }
        }
        cols = payload.cols
        rows = payload.rows
        overviewWidth = payload.overview_width
        overviewHeight = payload.overview_height
        stepMinutes = max(1, payload.step_minutes)
        fields = decodedFields
        pairs = pairMap
        pairsByFrom = fromMap
    }
}
