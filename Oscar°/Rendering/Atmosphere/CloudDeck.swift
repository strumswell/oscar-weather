//
//  CloudDeck.swift
//  Oscar°
//

import Foundation

struct CloudDeck: Equatable {
    var low: Float
    var mid: Float
    var high: Float

    init(total: Float) {
        self.init(low: total, mid: total * 0.55, high: total * 0.35)
    }

    init(low: Float, mid: Float, high: Float) {
        self.low = low
        self.mid = mid
        self.high = high
    }
}
