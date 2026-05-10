//
//  WeatherAtmosphericAdapter.swift
//  Oscar°
//
//  Compatibility facade for widget and legacy background callers.
//

import CoreLocation
import SwiftUI

final class WeatherAtmosphericAdapter {
    func generateAtmosphericSkyGradient(
        from weather: Weather,
        at location: CLLocationCoordinate2D
    ) -> LinearGradient {
        let snapshot = AtmosphereWeatherMapper.snapshot(from: weather, at: location)

        if weather.debug {
            print("AtmosphericAdapter: condition=\(snapshot.condition) cloud=\(snapshot.cloudCoverage) precip=\(snapshot.precipitationAmount)")
        }

        return AtmosphereSampler.skyGradient(snapshot: snapshot, sampleCount: 12)
    }

    func getAtmosphericCloudColor(
        from weather: Weather,
        at location: CLLocationCoordinate2D,
        isTop: Bool
    ) -> Color {
        let snapshot = AtmosphereWeatherMapper.snapshot(from: weather, at: location)
        return isTop
            ? AtmosphereSampler.cloudTopTint(snapshot: snapshot)
            : AtmosphereSampler.cloudBottomTint(snapshot: snapshot)
    }

    func getWidgetFullGradient(
        from weather: Weather,
        at location: CLLocationCoordinate2D
    ) -> LinearGradient {
        generateAtmosphericSkyGradient(from: weather, at: location)
    }

    func getWidgetBackgroundColors(
        from weather: Weather,
        at location: CLLocationCoordinate2D
    ) -> [Color] {
        AtmosphereSampler.widgetBackgroundColors(
            snapshot: AtmosphereWeatherMapper.snapshot(from: weather, at: location)
        )
    }
}
