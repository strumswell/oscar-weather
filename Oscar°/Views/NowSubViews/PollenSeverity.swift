//
//  PollenSeverity.swift
//  Oscar°
//

import Foundation

enum PollenTier: Int, Comparable {
    case none = 0, low, moderate, high, veryHigh

    static func < (lhs: PollenTier, rhs: PollenTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var severityFraction: Double {
        Double(rawValue) / 4.0
    }
}

enum PollenType {
    case alder, birch, grass, mugwort, ragweed

    func tier(for value: Double) -> PollenTier {
        switch self {
        case .alder:
            if value < 1 { return .none }
            if value <= 10 { return .low }
            if value <= 70 { return .moderate }
            if value <= 300 { return .high }
            return .veryHigh
        case .birch:
            if value < 1 { return .none }
            if value <= 10 { return .low }
            if value <= 50 { return .moderate }
            if value <= 300 { return .high }
            return .veryHigh
        case .grass:
            if value < 1 { return .none }
            if value <= 20 { return .low }
            if value <= 50 { return .moderate }
            if value <= 150 { return .high }
            return .veryHigh
        case .mugwort:
            if value < 1 { return .none }
            if value <= 5 { return .low }
            if value <= 15 { return .moderate }
            if value <= 50 { return .high }
            return .veryHigh
        case .ragweed:
            if value < 1 { return .none }
            if value <= 5 { return .low }
            if value <= 11 { return .moderate }
            if value <= 40 { return .high }
            return .veryHigh
        }
    }

    var displayMax: Int {
        switch self {
        case .alder, .birch: 300
        case .grass: 150
        case .mugwort: 50
        case .ragweed: 40
        }
    }
}
