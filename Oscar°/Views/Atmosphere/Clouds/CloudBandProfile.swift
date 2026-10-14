//
//  CloudBandProfile.swift
//  Oscar°
//

import Foundation

struct CloudBandProfile {
    let count: Int
    let scale: ClosedRange<Double>
    let yRange: ClosedRange<Double>
    let imagePool: [Int]
    let driftFactor: Double
    let presence: Double
    let shading: Double
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
