import Foundation

/// Weather code to SF Symbol. `sfSymbol(weathercode:isDay:isRaining:precipitation:)` is
/// radar-aware for the "now" widgets; `sfSymbol(weathercode:isDay:)` maps the code alone.
enum WeatherSymbol {
    static func sfSymbol(weathercode: Double, isDay: Bool = true) -> String {
        switch weathercode {
        case 0, 1: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 80, 81: return "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func sfSymbol(weathercode: Double, isDay: Double, isRaining: Bool, precipitation: Double) -> String {
        let raining = isRaining || precipitation > 0
        let day = isDay > 0
        switch weathercode {
        case 0, 1:
            return raining ? "cloud.drizzle.fill" : (day ? "sun.max.fill" : "moon.stars.fill")
        case 2:
            return raining ? "cloud.drizzle.fill" : (day ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3:
            return raining ? "cloud.drizzle.fill" : "cloud.fill"
        case 45, 48:
            return raining ? "cloud.drizzle.fill" : "cloud.fog.fill"
        case 51, 53, 55, 61, 63, 65:
            return raining ? "cloud.drizzle.fill" : "cloud.fill"
        case 56, 57:
            return raining ? "cloud.sleet.fill" : "cloud.fill"
        case 71, 73, 75, 77:
            return raining ? "cloud.snow.fill" : "cloud.fill"
        case 80, 81, 82, 85, 86:
            return raining ? "cloud.heavyrain.fill" : "cloud.fill"
        case 95, 96, 99:
            return raining ? "cloud.bolt.rain.fill" : "cloud.fill"
        default:
            return "cloud.fill"
        }
    }
}
