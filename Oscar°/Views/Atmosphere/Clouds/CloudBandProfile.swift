//
//  CloudBandProfile.swift
//  Oscar°
//

import Foundation

/// Every per-band tuning knob in one table. The sprites are soft-edged
/// (~15 % mean alpha over their box), so a band needs heavy overdraw before
/// it reads as a deck. Sized so a full mid band closes ~3/4 of what a full
/// low band does and a full high band ~1/3: an altostratus lid is overcast,
/// a cirrostratus veil whitens the sky without hiding it.
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
    /// Peak opacity of the uniform wash a closed band lays under its sprites.
    /// Sprites are broken cloud; a stratiform sky is a lid with no blue left,
    /// bright for cirrostratus, grey for altostratus, darkest for stratus.
    let veil: Double

    static let high = CloudBandProfile(
        count: 14, scale: 0.5...1.2, yRange: -60...120, imagePool: [1, 6, 5, 6],
        driftFactor: 0.35, presence: 0.7, shading: 0.15, veil: 0.55)
    static let mid = CloudBandProfile(
        count: 16, scale: 0.8...1.6, yRange: -60...190, imagePool: [2, 4, 5, 6, 1],
        driftFactor: 0.6, presence: 0.9, shading: 0.6, veil: 0.5)
    static let low = CloudBandProfile(
        count: 22, scale: 0.8...1.8, yRange: -90...300, imagePool: [0, 3, 4, 7, 2, 0],
        driftFactor: 1, presence: 1, shading: 1, veil: 0.4)
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
