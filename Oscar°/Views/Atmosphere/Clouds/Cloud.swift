//
//  Cloud.swift
//  Oscar°
//
//  Created by Paul Hudson on 12/11/2021.
//

import SwiftUI

final class Cloud {
    enum Band: CaseIterable {
        case high, mid, low
    }

    var position: CGPoint
    let band: Band
    let imageNumber: Int
    let scale: Double
    let threshold: Float
    let driftJitter = Double.random(in: 0.8...1.2)
    var wrapDistance: Double { max(620, 420 * scale) }

    init(band: Band, imageNumber: Int, scale: Double, threshold: Float, position: CGPoint) {
        self.band = band
        self.imageNumber = imageNumber
        self.scale = scale
        self.threshold = threshold
        self.position = position
    }

    func visibility(coverage: Float) -> Float {
        AtmosphereWeatherMapper.smoothstep(max(0, threshold - 0.15), threshold + 0.02, coverage)
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
