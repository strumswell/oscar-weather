//
//  RadarMotionData.swift
//  Oscar°
//
//  Decoded /radar/{region}/motion payload: per-pair flow fields for the
//  morph rendering and the motion arrows.
//

import Foundation

// MARK: - Motion fields (/radar/{region}/motion)

struct RadarMotionData: Sendable {
    struct Pair: Sendable {
        let fieldIndex: Int
        let gapMinutes: Int
    }

    let id = UUID()
    let cols: Int
    let rows: Int
    let overviewWidth: Int
    let overviewHeight: Int
    let stepMinutes: Int
    let fields: [[Float]]
    let pairs: [String: Pair]
    let pairsByFrom: [String: Pair]

    init?(payload: Components.Schemas.MotionResponse) {
        guard payload.cols > 1, payload.rows > 1,
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
