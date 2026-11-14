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

final class HomeProvider: PlaceTimelineSource {
    let client = APIClient.shared
    let refreshMinutes = 30

    func placeholder(in context: Context) -> HomeEntry {
        let placeholderGradient = LinearGradient(colors: [.sunriseStart, .sunnyDayEnd], startPoint: .top, endPoint: .bottom)
        return HomeEntry(date: Date(), location: "Berlin", temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", backgroundGradient: placeholderGradient)
    }

    func entries(for place: WidgetPlace) async throws -> [HomeEntry] {
        let coordinates = place.coordinates
        let locationName = await place.locationName()

        async let weatherRequest = client.getForecast(
            coordinates: coordinates,
            forecastDays: ._1,
            hourly: [
                .weathercode, .cloudcover, .relativehumidity_2m,
                .precipitation, .snowfall, .windspeed_10m, .winddirection_10m,
            ]
        )
        async let radarRequest = client.getRadarSeries(coordinates: coordinates)
        let weather = try await weatherRequest
        let precipSeries = try? await radarRequest

        let temperatureMin = weather.daily?.temperature_2m_min?.first ?? 0
        let temperatureMax = weather.daily?.temperature_2m_max?.first ?? 0
        let temperatureNow = weather.current?.temperature ?? 0
        let weathercode = weather.current?.weathercode ?? 0
        let isDay = weather.current?.is_day ?? 0
        let modelPrecipitation = weather.current?.precipitation ?? 0
        let gradient = await WeatherAtmosphericAdapter.widgetGradient(
            weather: weather, precipSeries: precipSeries, coordinates: coordinates
        )

        return nowcastEntryDates(refreshMinutes: refreshMinutes).map { date in
            let precipitation = precipSeries?.rate(at: date) ?? modelPrecipitation
            return HomeEntry(
                date: date,
                location: locationName,
                temperatureMin: temperatureMin,
                temperatureMax: temperatureMax,
                temperatureNow: temperatureNow,
                icon: WeatherSymbol.sfSymbol(weathercode: weathercode, isDay: isDay, isRaining: precipitation > 0, precipitation: precipitation),
                backgroundGradient: gradient
            )
        }
    }
}

extension WeatherAtmosphericAdapter {
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
