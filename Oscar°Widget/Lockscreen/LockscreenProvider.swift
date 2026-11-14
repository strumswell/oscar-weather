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

func currentWidgetCoordinates() async -> CLLocationCoordinate2D {
    await MainActor.run {
        LocationService.shared.update()
        return LocationService.shared.getCoordinates()
    }
}

func minutesFromNow(_ minutes: Int) -> Date {
    Calendar.current.date(byAdding: .minute, value: minutes, to: Date())!
}

struct WidgetPlace {
    let coordinates: CLLocationCoordinate2D
    var name: String? = nil

    var isFixed: Bool { name != nil }

    func locationName() async -> String {
        if let name { return name }
        return await LocationService.shared.getLocationName()
    }
}

#if os(iOS)
func widgetPlace(for cityID: String?) async -> WidgetPlace {
    if let cityID,
       let city = WidgetCity(id: cityID),
       !city.isCurrentLocation,
       city.latitude.isFinite,
       city.longitude.isFinite {
        return WidgetPlace(
            coordinates: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude),
            name: city.name
        )
    }
    return WidgetPlace(coordinates: await currentWidgetCoordinates())
}
#endif

protocol PlaceTimelineSource: TimelineProvider, Sendable {
    var refreshMinutes: Int { get }
    var retryMinutes: Int { get }
    func entries(for place: WidgetPlace) async throws -> [Entry]
}

extension PlaceTimelineSource {
    var retryMinutes: Int { 15 }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (Entry) -> ()) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<Entry>) -> ()) {
        Task {
            let place = WidgetPlace(coordinates: await currentWidgetCoordinates())
            completion(await timeline(for: place))
        }
    }

    func timeline(for place: WidgetPlace) async -> Timeline<Entry> {
        do {
            return Timeline(entries: try await entries(for: place), policy: .after(minutesFromNow(refreshMinutes)))
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
        await source.timeline(for: widgetPlace(for: configuration.city))
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
    let client = APIClient.shared
    let refreshMinutes = 30

    func placeholder(in context: Context) -> TemperatureLockScreenEntry {
        TemperatureLockScreenEntry(date: Date(), temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", precipitation: 2.5, precipitationProbability: 72)
    }

    func entries(for place: WidgetPlace) async throws -> [TemperatureLockScreenEntry] {
        let coordinates = place.coordinates
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

        return nowcastEntryDates(refreshMinutes: refreshMinutes).map { date in
            let precipitation = precipSeries?.rate(at: date) ?? modelPrecipitation
            let icon = WeatherSymbol.sfSymbol(weathercode: weathercode, isDay: isDay, isRaining: precipitation > 0, precipitation: precipitation)
            return TemperatureLockScreenEntry(date: date, temperatureMin: temperatureMin, temperatureMax: temperatureMax, temperatureNow: temperatureNow, icon: icon, precipitation: precipitation, precipitationProbability: Int(precipitationProbability ?? 0))
        }
    }

    public func getLocalizedHourIndex(weather: Operations.getForecast.Output.Ok.Body.jsonPayload) -> Int {
        let currentUnixTime = weather.current?.time ?? 0
        let hours = weather.hourly?.time ?? []
        return hours.indices.min { abs(currentUnixTime - hours[$0]) < abs(currentUnixTime - hours[$1]) } ?? 0
    }
}
