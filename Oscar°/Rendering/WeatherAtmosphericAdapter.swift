//
//  WeatherAtmosphericAdapter.swift
//  Oscar°
//
//  Compatibility facade for widget and legacy background callers.
//

import CoreLocation
import OSLog
import SwiftUI

@MainActor
final class WeatherAtmosphericAdapter {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "Atmosphere")

    func generateAtmosphericSkyGradient(
        from weather: Weather,
        at location: CLLocationCoordinate2D
    ) -> LinearGradient {
        let snapshot = AtmosphereWeatherMapper.snapshot(from: weather, at: location)

        if weather.debug {
            Self.logger.debug("AtmosphericAdapter: condition=\(String(describing: snapshot.condition), privacy: .public) cloud=\(snapshot.cloudCoverage, privacy: .public) precip=\(snapshot.precipitationAmount, privacy: .public)")
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
