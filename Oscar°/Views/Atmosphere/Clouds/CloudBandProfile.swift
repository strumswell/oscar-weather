//
//  CloudBandProfile.swift
//  Oscar°
//

import Foundation

/// Every per-band tuning knob in one table. Sized so a single band at full
/// cover closes the sky on its own: the sprites are soft-edged, so it takes
/// ~20× overdraw before no sky shows through. A full high band must read as
/// a cirrostratus veil, not a few wisps.
struct CloudBandProfile {
    let count: Int
    let scale: ClosedRange<Double>
    let yRange: ClosedRange<Double>
    let imagePool: [Int]
    /// Share of the low band's drift speed (parallax).
    let driftFactor: Double
    /// Peak opacity: far bands sit closer to the sky.
    let presence: Double
    /// Share of the top→bottom tint gradient a sprite shows: a thin cirrus
    /// veil has almost no shaded underside, a low deck the full one.
    let shading: Double

    static let high = CloudBandProfile(
        count: 12, scale: 0.3...0.9, yRange: -60...120, imagePool: [1, 6, 5, 6],
        driftFactor: 0.35, presence: 0.6, shading: 0.15)
    static let mid = CloudBandProfile(
        count: 14, scale: 0.45...1.0, yRange: -60...190, imagePool: [2, 4, 5, 6, 1],
        driftFactor: 0.6, presence: 0.8, shading: 0.6)
    static let low = CloudBandProfile(
        count: 22, scale: 0.8...1.8, yRange: -90...300, imagePool: [0, 3, 4, 7, 2, 0],
        driftFactor: 1, presence: 1, shading: 1)
}

extension Cloud.Band {
    var profile: CloudBandProfile {
        switch self {
        case .high: .high
        case .mid: .mid
        case .low: .low
        }
    }
}
