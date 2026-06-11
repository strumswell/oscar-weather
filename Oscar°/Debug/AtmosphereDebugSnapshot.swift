//
//  AtmosphereDebugSnapshot.swift
//  Oscar°
//
//  Synthetic snapshot builder for the hidden debug panel.
//

import Foundation

extension AtmosphereWeatherMapper {
    /// Fully synthetic snapshot for the hidden debug panel. Derived values
    /// (sun position, cloud density, haze, turbidity) follow the same
    /// formulas as the live mapper so visual tweaks transfer 1:1.
    static func debugSnapshot(
        timeOfDay: Float,
        condition: AtmosphereConditionFamily,
        intensity: Float,
        cloudCoverage: Float,
        windSpeed: Float,
        windDirectionDegrees: Float,
        aqiHaze: Float
    ) -> AtmosphereSnapshot {
        // Idealized solar arc: peaks at local noon, bottoms out at midnight.
        let maxElevation: Float = 58 * .pi / 180
        let sunElevation = sin(2 * .pi * (timeOfDay - 0.25)) * maxElevation
        let phase = daylightPhase(sunElevation: sunElevation)
        let nightAmount = 1 - smoothstep(-12, 0, sunElevation * 180 / .pi)

        let precipitationIntensity: Float
        switch condition {
        case .drizzle, .rain, .freezingRain, .showers, .thunderstorm:
            precipitationIntensity = intensity
        case .snow:
            precipitationIntensity = intensity * 0.5
        case .clear, .partlyCloudy, .overcast, .fog:
            precipitationIntensity = 0
        }
        let snowfallIntensity: Float = condition == .snow ? intensity : 0
        let thunderIntensity: Float = condition == .thunderstorm ? max(0.55, intensity) : 0

        let humidity = clamp(0.4 + cloudCoverage * 0.25 + intensity * 0.3, 0, 1)
        let cloudDensity = cloudDensityFor(
            condition: condition,
            cloudCoverage: cloudCoverage,
            humidity: humidity,
            precipitation: precipitationIntensity
        )
        let haze = clamp(
            humidity * 0.24
            + cloudCoverage * 0.18
            + precipitationIntensity * 0.28
            + aqiHaze * 0.34
            + (condition == .fog ? 0.65 : 0),
            0,
            1
        )
        let turbidity = clamp(
            0.12
            + humidity * 0.16
            + cloudDensity * 0.24
            + precipitationIntensity * 0.2
            + aqiHaze * 0.28,
            0,
            1
        )

        return AtmosphereSnapshot(
            // Deterministic in timeOfDay so the shader clock doesn't jump
            // while a slider is being dragged.
            timestamp: Double(timeOfDay) * 86_400,
            timeOfDay: timeOfDay,
            sunElevation: sunElevation,
            phase: phase,
            nightAmount: nightAmount,
            condition: condition,
            cloudCoverage: cloudCoverage,
            cloudDensity: cloudDensity,
            precipitationAmount: precipitationIntensity * 8,
            snowfallAmount: snowfallIntensity * 6,
            precipitationIntensity: precipitationIntensity,
            snowfallIntensity: snowfallIntensity,
            thunderIntensity: thunderIntensity,
            humidity: humidity,
            pressure: 1,
            haze: haze,
            turbidity: turbidity,
            windSpeed: clamp(windSpeed, 0, 1),
            windDirection: windDirectionDegrees * .pi / 180,
            aqiHaze: aqiHaze
        )
    }
}
