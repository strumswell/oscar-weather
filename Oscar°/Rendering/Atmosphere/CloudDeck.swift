//
//  CloudDeck.swift
//  Oscar°
//

import Foundation

/// Cover per altitude band, 0…1 (Open-Meteo: low < 3 km, mid 3–8 km, high
/// > 8 km). The sprite deck fades sprites in per band instead of swapping
/// whole decks at coverage thresholds. Compiled into every target that runs
/// the mapper, so it carries nothing view-side.
struct CloudDeck: Equatable {
    var low: Float
    var mid: Float
    var high: Float

    /// Split for snapshots without band data: mostly low, a thinner mid, a veil of high.
    init(total: Float) {
        self.init(low: total, mid: total * 0.55, high: total * 0.35)
    }

    init(low: Float, mid: Float, high: Float) {
        self.low = low
        self.mid = mid
        self.high = high
    }
}
