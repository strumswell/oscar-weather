import Foundation

enum WeatherConditionLabel {
    static func code(weathercode: Double, radarRate: Double?) -> Int {
        let code = Int(weathercode)
        guard let radarRate else { return code }
        if radarRate > 0, code < 51 { return radarRate >= 2.5 ? 61 : 51 }
        if radarRate <= 0, code >= 51 { return 3 }
        return code
    }

    /// The server's rain / sleet / snow call for a falling echo replaces the forecast's own
    /// word. 68 is the WMO code for rain and snow mixed.
    static func code(_ code: Int, radarKind: String?) -> Int {
        let snowy = (71...77).contains(code) || code == 85 || code == 86
        let rainy = (51...55).contains(code) || (61...65).contains(code) || (80...82).contains(code)
        guard snowy || rainy else { return code }
        switch radarKind {
        case "snow": return snowy ? code : 71
        case "sleet": return 68
        case "rain": return rainy ? code : 61
        default: return code
        }
    }

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
        case 68, 69:
            return String(localized: "Schneeregen")
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
        case .sleet:
            String(localized: "Schneeregen")
        case .snow:
            String(localized: "Schneefall")
        case .showers:
            String(localized: "Schauer")
        case .thunderstorm:
            String(localized: "Gewitter")
        }
    }

}
