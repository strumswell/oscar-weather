import SwiftUI

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

struct EnsembleConfidence {
    enum Level { case sure, fairlySure, fairlyUnsure, unsure }

    let level: Level
    let temperatureSpread: Double
    let rainIsOpen: Bool

    init(day: EnsembleDay) {
        let spreads = [day.high, day.low].compactMap { $0.map { $0.high - $0.low } }
        temperatureSpread = spreads.isEmpty ? 0 : spreads.reduce(0, +) / Double(spreads.count)
        let temperatureDoubt = temperatureSpread / 8
        let rainDoubt = 1 - abs(2 * day.wetShare - 1)
        rainIsOpen = rainDoubt > temperatureDoubt
        switch max(temperatureDoubt, rainDoubt) {
        case ..<0.3: level = .sure
        case ..<0.55: level = .fairlySure
        case ..<0.8: level = .fairlyUnsure
        default: level = .unsure
        }
    }

    var title: String {
        switch level {
        case .sure: String(localized: "Sicher")
        case .fairlySure: String(localized: "Ziemlich sicher")
        case .fairlyUnsure: String(localized: "Ziemlich unsicher")
        case .unsure: String(localized: "Unsicher")
        }
    }
}
