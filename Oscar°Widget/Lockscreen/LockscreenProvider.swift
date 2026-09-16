//
//  LockscreenProvider.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 10.04.23.
//

import Foundation
import CoreLocation
import SwiftUI
import WidgetKit

struct TemperatureLockScreenEntry: TimelineEntry {
    let date: Date
    let temperatureMin: Double
    let temperatureMax: Double
    let temperatureNow: Double
    let icon: String
    let precipitation: Double
    let precipitationProbability: Int
}

/// Shared timeline plumbing: resolve the location on the main actor, build one entry,
/// refresh after `refreshMinutes`. completion must always be called: a dropped
/// timeline request kills the refresh chain and the widget never updates again. An
/// empty timeline keeps the last rendered entry on screen and retries once the API
/// is back.
func runWidgetTimeline<Entry: TimelineEntry>(
    refreshMinutes: Int,
    retryMinutes: Int = 15,
    completion: @escaping @Sendable (Timeline<Entry>) -> (),
    make: @escaping @Sendable (CLLocationCoordinate2D) async throws -> Entry
) {
    Task {
        do {
            let coordinates = await MainActor.run {
                LocationService.shared.update()
                return LocationService.shared.getCoordinates()
            }
            let entry = try await make(coordinates)
            let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(nextUpdateDate)))
        } catch {
            let retryDate = Calendar.current.date(byAdding: .minute, value: retryMinutes, to: Date())!
            completion(Timeline(entries: [], policy: .after(retryDate)))
        }
    }
}

struct LockscreenProvider: TimelineProvider {
    let client = APIClient.shared

    func placeholder(in context: Context) -> TemperatureLockScreenEntry {
        TemperatureLockScreenEntry(date: Date(), temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", precipitation: 2.5, precipitationProbability: 72)
    }
    
    func getSnapshot(in context: Context, completion: @escaping @Sendable (TemperatureLockScreenEntry) -> ()) {
        let entry = TemperatureLockScreenEntry(date: Date(), temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", precipitation: 2.5, precipitationProbability: 72)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TemperatureLockScreenEntry>) -> ()) {
        runWidgetTimeline(refreshMinutes: 30, completion: completion) { coordinates in
            async let weatherRequest = client.getForecast(
                coordinates: coordinates,
                forecastDays: ._1,
                hourly: [.precipitation_probability]
            )
            async let radarRequest = client.getRadarSeries(coordinates: coordinates)
            let (weather, precipSeries) = try await (weatherRequest, radarRequest)

            let reportedMin = weather.daily?.temperature_2m_min?.first
            let reportedMax = weather.daily?.temperature_2m_max?.first
            let temperatureNow = weather.current?.temperature ?? 0
            let lowerTemperature = min(reportedMin ?? temperatureNow, reportedMax ?? temperatureNow)
            let upperTemperature = max(reportedMin ?? temperatureNow, reportedMax ?? temperatureNow)
            let temperatureMin = lowerTemperature < upperTemperature ? lowerTemperature : lowerTemperature - 0.5
            let temperatureMax = lowerTemperature < upperTemperature ? upperTemperature : upperTemperature + 0.5
            let weathercode = weather.current?.weathercode ?? 0
            let isDay = weather.current?.is_day ?? 0

            // Radar measures what is falling right now; the model's "current"
            // value is an interpolated guess (mirrors the Jetzt card's logic).
            let radarRate = precipSeries?.currentRate
            let precipitation = radarRate ?? (weather.current?.precipitation ?? 0.0)
            // Optional chaining only guards nil, not out-of-bounds: precipitation_probability
            // can be shorter than the time array, so index defensively.
            let probabilities = weather.hourly?.precipitation_probability ?? []
            let hourIndex = getLocalizedHourIndex(weather: weather)
            let precipitationProbability = probabilities.indices.contains(hourIndex) ? probabilities[hourIndex] : nil

            let isRaining = precipSeries?.isRaining() ?? false
            let icon = WeatherSymbol.sfSymbol(weathercode: weathercode, isDay: isDay, isRaining: isRaining, precipitation: precipitation)

            return TemperatureLockScreenEntry(date: Date(), temperatureMin: temperatureMin, temperatureMax: temperatureMax, temperatureNow: temperatureNow, icon: icon, precipitation: precipitation, precipitationProbability: Int(precipitationProbability ?? 0))
        }
    }

    /// Index of the forecast hour closest to the current time (first one on ties).
    public func getLocalizedHourIndex(weather: Operations.getForecast.Output.Ok.Body.jsonPayload) -> Int {
        let currentUnixTime = weather.current?.time ?? 0
        let hours = weather.hourly?.time ?? []
        return hours.indices.min { abs(currentUnixTime - hours[$0]) < abs(currentUnixTime - hours[$1]) } ?? 0
    }
}
