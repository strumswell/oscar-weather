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

struct ForecastHour: Identifiable {
    let id: Int
    let label: String
    let icon: String
    let temperature: Double
}

struct HomeEntry: TimelineEntry {
    let date: Date
    let location: String
    let temperatureNow: Double
    let temperatureMin: Double
    let temperatureMax: Double
    let icon: String
    let condition: String
    let hours: [ForecastHour]
    let days: [DayForecast]
    let rain: [Double]
    let rainHeadline: String?
    let rainDetail: String?
    let rainNow: Double?
    let backgroundGradient: LinearGradient
    var cityID: String? = nil
    var staleNote: String? = nil
    var timeZone: TimeZone = .current

    var hasRain: Bool { rain.contains { $0 > 0 } }
}

final class HomeProvider: PlaceTimelineSource {
    let refreshMinutes = 30

    func placeholder(in context: Context) -> HomeEntry {
        .rainSample
    }

    func entries(for place: WidgetPlace, family: WidgetFamily) async throws -> [HomeEntry] {
        let coordinates = place.coordinates
        let locationName = await place.locationName()
        async let radarRequest = WidgetForecast.radar(coordinates)
        let (weather, fetchedAt) = try await WidgetForecast.forecast(coordinates)
        let precipSeries = try? await radarRequest

        let timeZone = weather.locationTimeZone
        let temperatureNow = weather.current?.temperature ?? 0
        let weathercode = weather.current?.weathercode ?? 0
        let isDay = weather.current?.is_day ?? 0
        let days = DailyForecastProvider.days(from: weather, count: 5, labelsToday: false)
        let gradient = await WeatherAtmosphericAdapter.widgetGradient(
            weather: weather, precipSeries: precipSeries, coordinates: coordinates
        )

        return nowcastEntryDates(refreshMinutes: refreshMinutes).map { date in
            let radarRate = precipSeries?.rate(at: date)
            let code = WeatherConditionLabel.code(weathercode: weathercode, radarRate: radarRate)
            let points = RainNowcastSummary.points(from: precipSeries, now: date)
            let rainingNow = (points.first?.precipitation ?? 0) > 0
            return HomeEntry(
                date: date,
                location: locationName,
                temperatureNow: temperatureNow,
                temperatureMin: days.first?.low ?? temperatureNow,
                temperatureMax: days.first?.high ?? temperatureNow,
                icon: WeatherSymbol.sfSymbol(weathercode: Double(code), isDay: isDay, isRaining: code >= 51, precipitation: radarRate ?? 0),
                condition: WeatherConditionLabel.text(for: code),
                hours: Self.hours(from: weather, after: date),
                days: days,
                rain: RainNowcastSummary.values(points),
                rainHeadline: points.isEmpty ? nil : RainNowcastSummary.headline(for: points, now: date, timeZone: timeZone),
                rainDetail: rainingNow ? nil : RainNowcastSummary.peakText(in: points, withTime: true, timeZone: timeZone),
                rainNow: rainingNow ? points.first?.precipitation : nil,
                backgroundGradient: gradient,
                cityID: place.cityID,
                staleNote: staleText(fetchedAt, at: date, timeZone: timeZone),
                timeZone: timeZone
            )
        }
    }

    private static func hours(
        from weather: Operations.getForecast.Output.Ok.Body.jsonPayload,
        after date: Date
    ) -> [ForecastHour] {
        let times = weather.hourly?.time ?? []
        let temperatures = weather.hourly?.temperature_2m ?? []
        let codes = weather.hourly?.weathercode ?? []
        let isDay = weather.hourly?.is_day ?? []
        let start = times.firstIndex { $0 > date.timeIntervalSince1970 } ?? times.count
        let end = min(start + 6, times.count, temperatures.count, codes.count, isDay.count)
        guard start < end else { return [] }
        return (start..<end).map { index in
            ForecastHour(
                id: index,
                label: SettingService.formattedHour(
                    Date(timeIntervalSince1970: times[index]),
                    timeZone: weather.locationTimeZone
                ),
                icon: WeatherSymbol.sfSymbol(weathercode: codes[index], isDay: isDay[index] > 0),
                temperature: temperatures[index]
            )
        }
    }
}

extension HomeEntry {
    static var drySample: HomeEntry {
        sample(
            rain: Array(repeating: 0, count: RainNowcastSummary.maxBars),
            temperature: 7, icon: "cloud.sun.fill", weathercode: 2, gradient: .calmDay
        )
    }

    static var rainSample: HomeEntry {
        sample(rain: RainNowcastSummary.sampleComing, temperature: 7, icon: "cloud.fill", weathercode: 3, gradient: .rainyDay)
    }

    static var rainNowSample: HomeEntry {
        sample(rain: RainNowcastSummary.sampleRaining, temperature: 6, icon: "cloud.drizzle.fill", weathercode: 61, gradient: .rainyDay)
    }

    private static func sample(
        rain: [Double],
        temperature: Double,
        icon: String,
        weathercode: Int,
        gradient: LinearGradient
    ) -> HomeEntry {
        let now = Date.now
        let points = RainNowcastSummary.samplePoints(rain, now: now)
        let rainingNow = rain[0] > 0
        let hourIcons = ["cloud.sun.fill", "cloud.sun.fill", "cloud.fill", "cloud.fill", "cloud.moon.fill", "cloud.moon.fill"]
        let hourTemperatures: [Double] = [8, 7, 6, 5, 5, 4]
        let hours = hourIcons.indices.map { index in
            ForecastHour(
                id: index,
                label: SettingService.formattedHour(now.addingTimeInterval(Double(index + 1) * 3600)),
                icon: hourIcons[index],
                temperature: hourTemperatures[index]
            )
        }
        let dayIcons = ["cloud.rain.fill", "cloud.fill", "cloud.sun.fill", "sun.max.fill", "cloud.sun.fill"]
        let dayLows: [Double] = [3, 2, 4, 1, 2]
        let dayHighs: [Double] = [9, 8, 10, 6, 7]
        let days = dayIcons.indices.map { index in
            DayForecast(
                id: index,
                weekday: SettingService.formattedShortWeekday(now.addingTimeInterval(Double(index) * 86_400), timeZone: .current),
                icon: dayIcons[index],
                precipProbability: nil,
                precipSum: nil,
                low: dayLows[index],
                high: dayHighs[index]
            )
        }
        return HomeEntry(
            date: now,
            location: "Leipzig",
            temperatureNow: temperature,
            temperatureMin: 3,
            temperatureMax: 9,
            icon: icon,
            condition: WeatherConditionLabel.text(for: weathercode),
            hours: hours,
            days: days,
            rain: rain,
            rainHeadline: RainNowcastSummary.headline(for: points, now: now),
            rainDetail: rainingNow ? nil : RainNowcastSummary.peakText(in: points, withTime: true),
            rainNow: rainingNow ? rain[0] : nil,
            backgroundGradient: gradient
        )
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
