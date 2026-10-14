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

func nowcastEntryDates(refreshMinutes: Int, now: Date = Date()) -> [Date] {
    stride(from: 0, to: refreshMinutes, by: 5).map { now.addingTimeInterval(Double($0) * 60) }
}

func runWidgetTimeline<Entry: TimelineEntry>(
    refreshMinutes: Int,
    retryMinutes: Int = 15,
    completion: @escaping @Sendable (Timeline<Entry>) -> (),
    make: @escaping @Sendable (CLLocationCoordinate2D) async throws -> [Entry]
) {
    Task {
        do {
            let coordinates = await MainActor.run {
                LocationService.shared.update()
                return LocationService.shared.getCoordinates()
            }
            let entries = try await make(coordinates)
            let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: Date())!
            completion(Timeline(entries: entries, policy: .after(nextUpdateDate)))
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
            let weather = try await weatherRequest
            let precipSeries = try? await radarRequest

            let reportedMin = weather.daily?.temperature_2m_min?.first
            let reportedMax = weather.daily?.temperature_2m_max?.first
            let temperatureNow = weather.current?.temperature ?? 0
            let lowerTemperature = min(reportedMin ?? temperatureNow, reportedMax ?? temperatureNow)
            let upperTemperature = max(reportedMin ?? temperatureNow, reportedMax ?? temperatureNow)
            let temperatureMin = lowerTemperature < upperTemperature ? lowerTemperature : lowerTemperature - 0.5
            let temperatureMax = lowerTemperature < upperTemperature ? upperTemperature : upperTemperature + 0.5
            let weathercode = weather.current?.weathercode ?? 0
            let isDay = weather.current?.is_day ?? 0

            let modelPrecipitation = weather.current?.precipitation ?? 0
            let probabilities = weather.hourly?.precipitation_probability ?? []
            let hourIndex = getLocalizedHourIndex(weather: weather)
            let precipitationProbability = probabilities.indices.contains(hourIndex) ? probabilities[hourIndex] : nil

            return nowcastEntryDates(refreshMinutes: 30).map { date in
                let precipitation = precipSeries?.rate(at: date) ?? modelPrecipitation
                let icon = WeatherSymbol.sfSymbol(weathercode: weathercode, isDay: isDay, isRaining: precipitation > 0, precipitation: precipitation)
                return TemperatureLockScreenEntry(date: date, temperatureMin: temperatureMin, temperatureMax: temperatureMax, temperatureNow: temperatureNow, icon: icon, precipitation: precipitation, precipitationProbability: Int(precipitationProbability ?? 0))
            }
        }
    }

    public func getLocalizedHourIndex(weather: Operations.getForecast.Output.Ok.Body.jsonPayload) -> Int {
        let currentUnixTime = weather.current?.time ?? 0
        let hours = weather.hourly?.time ?? []
        return hours.indices.min { abs(currentUnixTime - hours[$0]) < abs(currentUnixTime - hours[$1]) } ?? 0
    }
}
