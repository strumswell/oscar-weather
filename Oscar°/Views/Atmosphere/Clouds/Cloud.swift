//
//  Cloud.swift
//  Oscar°
//
//  Created by Paul Hudson on 12/11/2021.
//

import SwiftUI

/// One sprite in the deck. Layout (band, image, size, threshold) is fixed for
/// the deck's lifetime; only `position` moves.
final class Cloud {
    /// Draw order = distance: high first, low (nearest, fastest) last.
    enum Band: CaseIterable {
        case high, mid, low
    }

    var position: CGPoint
    let band: Band
    let imageNumber: Int
    let scale: Double
    /// Band cover at which this sprite fades in.
    let threshold: Float
    let driftJitter = Double.random(in: 0.8...1.2)

    init(band: Band, imageNumber: Int, scale: Double, threshold: Float, position: CGPoint) {
        self.band = band
        self.imageNumber = imageNumber
        self.scale = scale
        self.threshold = threshold
        self.position = position
    }

    /// 0…1 presence for a band cover; sprites appear in threshold order so the
    /// visible count grows with cover, small ones first.
    func visibility(coverage: Float) -> Float {
        AtmosphereWeatherMapper.smoothstep(threshold - 0.15, threshold + 0.02, coverage)
    }
}

extension CloudDeck {
    subscript(band: Cloud.Band) -> Float {
        switch band {
        case .low: low
        case .mid: mid
        case .high: high
        }
    }
}
