//
//  HomeProvider.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 03.06.23.
//

import Foundation
import CoreLocation
import SwiftUI
import WidgetKit
import simd

struct HomeEntry: TimelineEntry {
    let date: Date
    let location: String
    let temperatureMin: Double
    let temperatureMax: Double
    let temperatureNow: Double
    let icon: String
    let backgroundGradient: LinearGradient
}

final class HomeProvider: TimelineProvider, Sendable {
    let client = APIClient.shared

    func placeholder(in context: Context) -> HomeEntry {
        let placeholderGradient = LinearGradient(colors: [.sunriseStart, .sunnyDayEnd], startPoint: .top, endPoint: .bottom)
        return HomeEntry(date: Date(), location: "Berlin", temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", backgroundGradient: placeholderGradient)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (HomeEntry) -> ()) {
        let placeholderGradient = LinearGradient(colors: [.sunriseStart, .sunnyDayEnd], startPoint: .top, endPoint: .bottom)
        let entry = HomeEntry(date: Date(), location: "Berlin", temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", backgroundGradient: placeholderGradient)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<HomeEntry>) -> ()) {
        runWidgetTimeline(refreshMinutes: 30, completion: completion) { coordinates in
            let locationName = await LocationService.shared.getLocationName()

            async let weatherRequest = self.client.getForecast(
                coordinates: coordinates,
                forecastDays: ._1,
                hourly: [
                    .weathercode, .cloudcover, .relativehumidity_2m,
                    .precipitation, .snowfall, .windspeed_10m, .winddirection_10m,
                ]
            )
            async let radarRequest = self.client.getRadarSeries(coordinates: coordinates)
            let (weather, precipSeries) = try await (weatherRequest, radarRequest)

            let temperatureMin = weather.daily?.temperature_2m_min?.first ?? 0
            let temperatureMax = weather.daily?.temperature_2m_max?.first ?? 0
            let temperatureNow = weather.current?.temperature ?? 0
            let weathercode = weather.current?.weathercode ?? 0
            let isDay = weather.current?.is_day ?? 0
            // Radar measures what is falling right now; the model's "current"
            // value is an interpolated guess (mirrors the lockscreen provider).
            let precipitation = precipSeries?.currentRate ?? (weather.current?.precipitation ?? 0)

            return HomeEntry(
                date: Date(),
                location: locationName,
                temperatureMin: temperatureMin,
                temperatureMax: temperatureMax,
                temperatureNow: temperatureNow,
                icon: WeatherSymbol.sfSymbol(weathercode: weathercode, isDay: isDay, isRaining: precipSeries?.isRaining() ?? false, precipitation: precipitation),
                backgroundGradient: await WeatherAtmosphericAdapter.widgetGradient(
                    weather: weather, precipSeries: precipSeries, coordinates: coordinates
                )
            )
        }
    }
}

extension WeatherAtmosphericAdapter {
    /// Build the atmospheric gradient on the main actor (Weather + adapter are
    /// @MainActor); only the resulting Sendable gradient crosses back.
    nonisolated static func widgetGradient(
        weather: Operations.getForecast.Output.Ok.Body.jsonPayload,
        precipSeries: PrecipSeriesResponse?,
        coordinates: CLLocationCoordinate2D
    ) async -> LinearGradient {
        let dayBegin = weather.hourly?.time.first ?? 0
        return await MainActor.run {
            let weatherForRendering = Weather()
            weatherForRendering.time = (Date.now.timeIntervalSince1970 - Double(dayBegin)) / 86400.0
            weatherForRendering.forecast = weather
            weatherForRendering.precipSeries = precipSeries
            return WeatherAtmosphericAdapter().getWidgetFullGradient(from: weatherForRendering, at: coordinates)
        }
    }
}
