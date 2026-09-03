import SwiftUI

/// European Air Quality Index bands: 0-20 good up to >100 extremely poor.
enum EUAirQualityBand: CaseIterable {
    case good, fair, moderate, poor, veryPoor, extremelyPoor

    init(value: Double) {
        switch value {
        case ..<20: self = .good
        case ..<40: self = .fair
        case ..<60: self = .moderate
        case ..<80: self = .poor
        case ..<100: self = .veryPoor
        default: self = .extremelyPoor
        }
    }

    var lowerBound: Double {
        switch self {
        case .good: 0
        case .fair: 20
        case .moderate: 40
        case .poor: 60
        case .veryPoor: 80
        case .extremelyPoor: 100
        }
    }

    /// nil for the open-ended top band.
    var upperBound: Double? {
        switch self {
        case .good: 20
        case .fair: 40
        case .moderate: 60
        case .poor: 80
        case .veryPoor: 100
        case .extremelyPoor: nil
        }
    }

    var color: Color {
        switch self {
        case .good: Color(red: 79 / 255, green: 240 / 255, blue: 230 / 255)
        case .fair: Color(red: 81 / 255, green: 204 / 255, blue: 170 / 255)
        case .moderate: Color(red: 240 / 255, green: 230 / 255, blue: 65 / 255)
        case .poor: Color(red: 255 / 255, green: 81 / 255, blue: 80 / 255)
        case .veryPoor: Color(red: 150 / 255, green: 1 / 255, blue: 50 / 255)
        case .extremelyPoor: Color(red: 125 / 255, green: 33 / 255, blue: 129 / 255)
        }
    }

    var statusKey: String {
        switch self {
        case .good: "Gut"
        case .fair: "Akzeptabel"
        case .moderate: "Mäßig"
        case .poor: "Schlecht"
        case .veryPoor: "Sehr schlecht"
        case .extremelyPoor: "Extrem schlecht"
        }
    }

    var localizedStatus: String {
        String(localized: String.LocalizationValue(statusKey))
    }

    /// Gauge gradient on a 0...100 scale: each band's color at its start.
    static let gradientStops: [(location: Double, color: Color)] = allCases.map { ($0.lowerBound / 100, $0.color) }
}
