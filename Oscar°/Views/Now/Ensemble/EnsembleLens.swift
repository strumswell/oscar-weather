import SwiftUI

/// One row of the ensemble deck.
enum EnsembleLens: CaseIterable, Identifiable {
    case sky, high, low, precipitation, wind

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .sky: "Himmel"
        case .high: "Höchstwert"
        case .low: "Tiefstwert"
        case .precipitation: "Niederschlag"
        case .wind: "Wind"
        }
    }

    var systemImage: String {
        switch self {
        case .sky: "cloud.sun"
        case .high: "thermometer.high"
        case .low: "thermometer.low"
        case .precipitation: "drop"
        case .wind: "wind"
        }
    }

    var color: Color {
        switch self {
        case .sky: .yellow
        case .high: .red
        case .low: .cyan
        case .precipitation: .hourlyRain
        case .wind: .teal
        }
    }
}

extension EnsembleSky {
    var title: String {
        switch self {
        case .sun: String(localized: "Sonne")
        case .clouds: String(localized: "Wolken")
        case .rain: String(localized: "Regen")
        case .snow: String(localized: "Schnee")
        }
    }

    var color: Color {
        switch self {
        case .sun: .yellow
        case .clouds: Color(white: 0.72)
        case .rain: .hourlyRain
        case .snow: .white
        }
    }
}

/// How far a day's runs agree, in words: the page's headline.
enum EnsembleConfidence {
    case sure, fairlySure, fairlyUnsure, unsure

    /// Doubt grows with the eight-in-ten spread of highs and lows (8 °C is
    /// fully open) and with runs disagreeing on the weather.
    init(day: EnsembleDay, fahrenheit: Bool) {
        let degrees = fahrenheit ? 1 / 1.8 : 1
        let spreads = [day.high, day.low].compactMap { $0.map { ($0.high - $0.low) * degrees } }
        let temperatureDoubt = spreads.isEmpty ? 0 : spreads.reduce(0, +) / Double(spreads.count) / 8
        let skyDoubt = day.sky.dominant.map { (1 - day.sky.share(of: $0)) / 0.8 } ?? 0
        switch max(temperatureDoubt, skyDoubt) {
        case ..<0.3: self = .sure
        case ..<0.55: self = .fairlySure
        case ..<0.8: self = .fairlyUnsure
        default: self = .unsure
        }
    }

    var title: String {
        switch self {
        case .sure: String(localized: "Sicher")
        case .fairlySure: String(localized: "Ziemlich sicher")
        case .fairlyUnsure: String(localized: "Ziemlich unsicher")
        case .unsure: String(localized: "Unsicher")
        }
    }
}
