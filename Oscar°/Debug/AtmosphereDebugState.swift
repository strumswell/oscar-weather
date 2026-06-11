//
//  AtmosphereDebugState.swift
//  Oscar°
//
//  Override state for the hidden debug panel (10 taps on the head view).
//  When enabled, the weather simulation renders this synthetic state instead
//  of live weather, so visuals can be inspected for any time of day,
//  condition, and intensity.
//

import Foundation
import Observation

@Observable
final class AtmosphereDebugState {
    var overrideEnabled = false
    /// Local time as a day fraction (0 = midnight, 0.5 = noon).
    var timeOfDay: Double = 0.5
    var condition: AtmosphereConditionFamily = .clear
    /// Strength of the active phenomenon (rain/snow/thunder), 0…1.
    var intensity: Double = 0.5
    var cloudCoverage: Double = 0.3
    var windSpeed: Double = 0.2
    var windDirectionDegrees: Double = 90
    var aqiHaze: Double = 0
    var moonPhase: Double = 0.5

    var snapshot: AtmosphereSnapshot {
        AtmosphereWeatherMapper.debugSnapshot(
            timeOfDay: Float(timeOfDay),
            condition: condition,
            intensity: Float(intensity),
            cloudCoverage: Float(cloudCoverage),
            windSpeed: Float(windSpeed),
            windDirectionDegrees: Float(windDirectionDegrees),
            aqiHaze: Float(aqiHaze)
        )
    }
}

extension AtmosphereConditionFamily {
    static let debugCases: [AtmosphereConditionFamily] = [
        .clear, .partlyCloudy, .overcast, .fog, .drizzle,
        .rain, .freezingRain, .snow, .showers, .thunderstorm
    ]

    var debugLabel: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly Cloudy"
        case .overcast: return "Overcast"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .freezingRain: return "Freezing Rain"
        case .snow: return "Snow"
        case .showers: return "Showers"
        case .thunderstorm: return "Thunderstorm"
        }
    }
}
