import Foundation

/// Weather-code families as short labels, shared by the app and the watch.
enum WeatherConditionLabel {
    static func text(for code: Int) -> String {
        switch code {
        case 0, 1:
            return String(localized: "Klar")
        case 2:
            return String(localized: "Teils bewölkt")
        case 3:
            return String(localized: "Bedeckt")
        case 45, 48:
            return String(localized: "Nebel")
        case 51...57:
            return String(localized: "Nieselregen")
        case 61...65:
            return String(localized: "Regen")
        case 66, 67:
            return String(localized: "Gefrierender Regen")
        case 71...77, 85, 86:
            return String(localized: "Schneefall")
        case 80...82:
            return String(localized: "Schauer")
        case 95...99:
            return String(localized: "Gewitter")
        default:
            return String(localized: "Bewölkt")
        }
    }

    /// Label for an already-derived condition family (the mapper may have
    /// upgraded a dry code to rain based on radar).
    static func text(for family: AtmosphereConditionFamily) -> String {
        switch family {
        case .clear:
            String(localized: "Klar")
        case .partlyCloudy:
            String(localized: "Teils bewölkt")
        case .overcast:
            String(localized: "Bedeckt")
        case .fog:
            String(localized: "Nebel")
        case .drizzle:
            String(localized: "Nieselregen")
        case .rain:
            String(localized: "Regen")
        case .freezingRain:
            String(localized: "Gefrierender Regen")
        case .snow:
            String(localized: "Schneefall")
        case .showers:
            String(localized: "Schauer")
        case .thunderstorm:
            String(localized: "Gewitter")
        }
    }

}
