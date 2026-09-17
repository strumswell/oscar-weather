import CoreLocation
import Foundation
import simd
import SwiftUI

enum AtmosphereConditionFamily: CaseIterable {
    case clear, partlyCloudy, overcast, fog, drizzle, rain, freezingRain, snow, showers, thunderstorm
}

struct AtmosphereSnapshot: Equatable {
    let timestamp: Double
    let timeOfDay: Float
    let sunElevation: Float
    let phase: Float
    let nightAmount: Float
    let condition: AtmosphereConditionFamily
    let cloudCoverage: Float
    let cloudDensity: Float
    let precipitationAmount: Float
    let snowfallAmount: Float
    let precipitationIntensity: Float
    let snowfallIntensity: Float
    let thunderIntensity: Float
    let haze: Float
    let turbidity: Float
    let windSpeed: Float
    let windDirection: Float
    let aqiHaze: Float

    static let fallback = AtmosphereSnapshot(
        timestamp: Date.now.timeIntervalSince1970,
        timeOfDay: 0.5,
        sunElevation: 0.7,
        phase: 1,
        nightAmount: 0,
        condition: .clear,
        cloudCoverage: 0,
        cloudDensity: 0,
        precipitationAmount: 0,
        snowfallAmount: 0,
        precipitationIntensity: 0,
        snowfallIntensity: 0,
        thunderIntensity: 0,
        haze: 0.08,
        turbidity: 0.22,
        windSpeed: 0,
        windDirection: 0,
        aqiHaze: 0
    )

    /// A calm, clear twilight with visible stars. Used as the backdrop before any forecast
    /// has loaded — first launch, or a cold-start fetch failure — instead of a flat gradient.
    /// Deep civil twilight (sun ≈ 8° below the horizon): a blue dusk sky with the stars out
    /// and no clouds, wind, or precipitation.
    static let twilight = AtmosphereSnapshot(
        timestamp: Date.now.timeIntervalSince1970,
        timeOfDay: 0.9,
        sunElevation: -0.14,
        phase: 0,
        nightAmount: 0.78,
        condition: .clear,
        cloudCoverage: 0,
        cloudDensity: 0,
        precipitationAmount: 0,
        snowfallAmount: 0,
        precipitationIntensity: 0,
        snowfallIntensity: 0,
        thunderIntensity: 0,
        haze: 0.05,
        turbidity: 0.18,
        windSpeed: 0,
        windDirection: 0,
        aqiHaze: 0
    )
}

extension AtmosphereSnapshot {
    typealias Vector = AnimatableValues<
        Double, Float, Float, Float, Float, Float, Float, Float, Float,
        Float, Float, Float, Float, Float, Float, Float, Float
    >

    /// Every continuous field as one animatable vector, so the sim can tween
    /// between scrubbed hours instead of cutting; `condition` stays discrete.
    var vector: Vector {
        AnimatableValues(
            timestamp, timeOfDay, sunElevation, phase, nightAmount,
            cloudCoverage, cloudDensity, precipitationAmount, snowfallAmount,
            precipitationIntensity, snowfallIntensity, thunderIntensity,
            haze, turbidity, windSpeed, windDirection, aqiHaze
        )
    }

    init(vector: Vector, condition: AtmosphereConditionFamily) {
        let v = vector.value
        self.init(
            timestamp: v.0, timeOfDay: v.1, sunElevation: v.2, phase: v.3, nightAmount: v.4,
            condition: condition,
            cloudCoverage: v.5, cloudDensity: v.6, precipitationAmount: v.7, snowfallAmount: v.8,
            precipitationIntensity: v.9, snowfallIntensity: v.10, thunderIntensity: v.11,
            haze: v.12, turbidity: v.13, windSpeed: v.14, windDirection: v.15, aqiHaze: v.16
        )
    }

    /// Visibility of the drawn sun DISC: 1 in daylight, fading out as the sun
    /// approaches the horizon, 0 once it dips below. Distinct from `phase`,
    /// which deliberately keeps ambient light through twilight — gating the
    /// disc on `phase` used to float a faint sun in a twilight sky.
    var sunDiscVisibility: Float {
        AtmosphereWeatherMapper.smoothstep(0, 4, sunElevation * 180 / .pi)
    }
}
