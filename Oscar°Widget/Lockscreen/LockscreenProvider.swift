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
    var condition = ""
    var rainHeadline: String? = nil
    var cityID: String? = nil
    var staleNote: String? = nil
}

func nowcastEntryDates(refreshMinutes: Int, now: Date = Date()) -> [Date] {
    stride(from: 0, to: refreshMinutes, by: 5).map { now.addingTimeInterval(Double($0) * 60) }
}

func minutesFromNow(_ minutes: Int) -> Date {
    Calendar.current.date(byAdding: .minute, value: minutes, to: Date())!
}

func staleText(_ fetchedAt: Date, at date: Date, timeZone: TimeZone = .current) -> String? {
    guard date.timeIntervalSince(fetchedAt) > 3600 else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var time = SettingService.formattedTime(fetchedAt, timeZone: timeZone)
    if !calendar.isDate(fetchedAt, inSameDayAs: date) {
        time = SettingService.formattedShortWeekday(fetchedAt, timeZone: timeZone) + " " + time
    }
    return String(localized: "Stand \(time)", comment: "Widget: Daten von HH:MM")
}

extension RainNowcastSummary {
    static func peakText(in points: [PrecipPoint], withTime: Bool, timeZone: TimeZone = .current) -> String? {
        guard let peak = peak(in: points) else { return nil }
        let rate = "\(RainIntensity.format(peak.precipitation)) \(RainIntensity.unit)"
        guard withTime else {
            return String(localized: "Bis zu \(rate)", comment: "Widget Regenverlauf: stärkster Regen der nächsten 90 Minuten")
        }
        return String(localized: "Bis zu \(rate) gegen \(SettingService.formattedTime(peak.timestamp, timeZone: timeZone))")
    }
}

protocol PlaceTimelineSource: TimelineProvider, Sendable {
    var refreshMinutes: Int { get }
    var retryMinutes: Int { get }
    func entries(for place: WidgetPlace, family: WidgetFamily) async throws -> [Entry]
}

extension PlaceTimelineSource {
    var retryMinutes: Int { 15 }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (Entry) -> ()) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<Entry>) -> ()) {
        let family = context.family
        Task {
            let place = WidgetPlace(coordinates: await currentWidgetCoordinates())
            completion(await timeline(for: place, family: family))
        }
    }

    func timeline(for place: WidgetPlace, family: WidgetFamily) async -> Timeline<Entry> {
        do {
            return Timeline(entries: try await entries(for: place, family: family), policy: .after(minutesFromNow(refreshMinutes)))
        } catch {
            return Timeline(entries: [], policy: .after(minutesFromNow(retryMinutes)))
        }
    }
}

#if os(iOS)
struct PlaceIntentProvider<Source: PlaceTimelineSource>: AppIntentTimelineProvider {
    let source: Source

    func placeholder(in context: Context) -> Source.Entry {
        source.placeholder(in: context)
    }

    func snapshot(for configuration: SelectCityIntent, in context: Context) async -> Source.Entry {
        source.placeholder(in: context)
    }

    func timeline(for configuration: SelectCityIntent, in context: Context) async -> Timeline<Source.Entry> {
        await source.timeline(for: widgetPlace(for: configuration.city), family: context.family)
    }
}
#endif

@MainActor
func placeConfiguration<Source: PlaceTimelineSource, Content: View>(
    kind: String,
    source: Source,
    @ViewBuilder content: @escaping (Source.Entry) -> Content
) -> some WidgetConfiguration {
    #if os(iOS)
    return AppIntentConfiguration(
        kind: kind,
        intent: SelectCityIntent.self,
        provider: PlaceIntentProvider(source: source),
        content: content
    )
    #else
    return StaticConfiguration(kind: kind, provider: source, content: content)
    #endif
}

struct LockscreenProvider: PlaceTimelineSource {
    let refreshMinutes = 30

    func placeholder(in context: Context) -> TemperatureLockScreenEntry {
        TemperatureLockScreenEntry(date: Date(), temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", precipitation: 2.5, precipitationProbability: 72, condition: WeatherConditionLabel.text(for: 2))
    }

    func entries(for place: WidgetPlace, family: WidgetFamily) async throws -> [TemperatureLockScreenEntry] {
        let coordinates = place.coordinates
        async let radarRequest = WidgetForecast.radar(coordinates)
        let (weather, fetchedAt) = try await WidgetForecast.forecast(coordinates)
        let precipSeries = try? await radarRequest
        let timeZone = weather.locationTimeZone

        let today = weather.dayIndex(at: Date())
        let reportedMin = weather.daily?.temperature_2m_min?[safe: today]
        let reportedMax = weather.daily?.temperature_2m_max?[safe: today]
        let temperatureNow = weather.current?.temperature ?? 0
        let lowerTemperature = min(reportedMin ?? temperatureNow, reportedMax ?? temperatureNow)
        let upperTemperature = max(reportedMin ?? temperatureNow, reportedMax ?? temperatureNow)
        let temperatureMin = lowerTemperature < upperTemperature ? lowerTemperature : lowerTemperature - 0.5
        let temperatureMax = lowerTemperature < upperTemperature ? upperTemperature : upperTemperature + 0.5
        let weathercode = weather.current?.weathercode ?? 0
        let isDay = weather.current?.is_day ?? 0
        let modelPrecipitation = weather.current?.precipitation ?? 0
        let probabilities = weather.hourly?.precipitation_probability ?? []

        return nowcastEntryDates(refreshMinutes: refreshMinutes).map { date in
            let radarRate = precipSeries?.rate(at: date)
            let code = WeatherConditionLabel.code(weathercode: weathercode, radarRate: radarRate)
            let icon = WeatherSymbol.sfSymbol(weathercode: Double(code), isDay: isDay, isRaining: code >= 51, precipitation: radarRate ?? 0)
            let points = RainNowcastSummary.points(from: precipSeries, now: date)
            let rainHeadline = points.contains { $0.precipitation > 0 } ? RainNowcastSummary.headline(for: points, now: date, timeZone: timeZone) : nil
            let probability = probabilities[safe: weather.hourIndex(at: date)] ?? nil
            return TemperatureLockScreenEntry(
                date: date,
                temperatureMin: temperatureMin,
                temperatureMax: temperatureMax,
                temperatureNow: temperatureNow,
                icon: icon,
                precipitation: radarRate ?? modelPrecipitation,
                precipitationProbability: Int(probability ?? 0),
                condition: WeatherConditionLabel.text(for: code),
                rainHeadline: rainHeadline,
                cityID: place.cityID,
                staleNote: staleText(fetchedAt, at: date, timeZone: timeZone)
            )
        }
    }
}
