import SwiftUI

/// WHO exposure categories, decided on the rounded index like the WHO tables.
enum UVIndexCategory: CaseIterable {
    case low, moderate, high, veryHigh, extreme

    init(uvIndex: Double) {
        switch Int(uvIndex.rounded()) {
        case ..<3: self = .low
        case 3...5: self = .moderate
        case 6...7: self = .high
        case 8...10: self = .veryHigh
        default: self = .extreme
        }
    }

    /// Continuous value span used for chart bands. The edges sit where the rounded
    /// index changes category, so a band never contradicts the badge.
    var range: Range<Double> {
        switch self {
        case .low: 0..<2.5
        case .moderate: 2.5..<5.5
        case .high: 5.5..<7.5
        case .veryHigh: 7.5..<10.5
        case .extreme: 10.5..<Double.infinity
        }
    }

    var color: Color {
        switch self {
        case .low: .green
        case .moderate: .yellow
        case .high: .orange
        case .veryHigh: .red
        case .extreme: .purple
        }
    }

    var titleKey: String {
        switch self {
        case .low: "Niedrig"
        case .moderate: "Mäßig"
        case .high: "Hoch"
        case .veryHigh: "Sehr hoch"
        case .extreme: "Extrem"
        }
    }

    var title: LocalizedStringKey { LocalizedStringKey(titleKey) }
    var localizedTitle: String { String(localized: String.LocalizationValue(titleKey)) }

    var riskTitleKey: String {
        switch self {
        case .low: "Geringe gesundheitliche Gefährdung"
        case .moderate: "Mittlere gesundheitliche Gefährdung, Schutzmaßnahmen sind erforderlich."
        case .high: "Hohe gesundheitliche Gefährdung, Schutzmaßnahmen sind erforderlich."
        case .veryHigh: "Sehr hohe gesundheitliche Gefährdung, Schutzmaßnahmen sind unbedingt erforderlich."
        case .extreme: "Extreme gesundheitliche Gefährdung, Besondere Schutzmaßnahmen sind ein Muss."
        }
    }

    var riskBodyKey: String {
        switch self {
        case .low: "Bei diesem UV-Wert besteht nur eine geringe gesundheitliche Gefährdung. Meist sind keine besonderen Schutzmaßnahmen erforderlich."
        case .moderate: "Hemd, Sonnencreme und Sonnenbrille schützen vor zu viel UV-Strahlung."
        case .high: "Die Weltgesundheitsorganisation (WHO) rät, mittags den Schatten zu suchen. In der Sonne werden Hemd, Sonnencreme, Sonnenbrille und Kopfbedeckung benötigt."
        case .veryHigh: "Die Weltgesundheitsorganisation (WHO) rät, zwischen 11 und 16 Uhr den Aufenthalt im Freien zu vermeiden, aber auch im Schatten gehören ein sonnendichtes Hemd, lange Hosen, Sonnencreme, Sonnenbrille und ein breitkrempiger Hut zum sonnengerechten Verhalten."
        case .extreme: "Die Weltgesundheitsorganisation (WHO) empfiehlt, zwischen 11 und 16 Uhr im Schutz eines Hauses zu bleiben und auch außerhalb dieser Zeit unbedingt Schatten zu suchen. Ein sonnendichtes Hemd, lange Hosen, Sonnencreme, Sonnenbrille und ein breitkrempiger Hut sind auch im Schatten unerlässlich."
        }
    }
}
