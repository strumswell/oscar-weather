import CoreLocation
import Foundation
import WidgetKit

struct DailyForecastProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DailyForecastEntry {
        .placeholder
    }

    func snapshot(for configuration: SelectCityIntent, in context: Context) async -> DailyForecastEntry {
        context.isPreview ? placeholder(in: context) : await makeEntry(for: configuration, family: context.family)
    }

    func timeline(for configuration: SelectCityIntent, in context: Context) async -> Timeline<DailyForecastEntry> {
        let entry = await makeEntry(for: configuration, family: context.family)
        let nextRefresh: TimeInterval = entry.days.isEmpty ? 15 * 60 : 60 * 60
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(nextRefresh)))
    }

    private func makeEntry(for configuration: SelectCityIntent, family: WidgetFamily) async -> DailyForecastEntry {
        let place = await widgetPlace(for: configuration.city?.id)
        let name = await place.locationName()
        do {
            return try await forecastEntry(coordinates: place.coordinates, locationName: name, cityID: place.cityID, family: family)
        } catch {
            return .unavailable(location: name, cityID: place.cityID)
        }
    }

    private func forecastEntry(
        coordinates: CLLocationCoordinate2D,
        locationName: String,
        cityID: String?,
        family: WidgetFamily
    ) async throws -> DailyForecastEntry {
        async let radarRequest = WidgetForecast.radar(coordinates)
        let (weather, fetchedAt) = try await family == .systemLarge
            ? WidgetForecast.daily(coordinates)
            : WidgetForecast.forecast(coordinates)
        let precipSeries = try? await radarRequest

        let days = Self.days(from: weather, count: 9)

        let lows = days.map(\.low)
        let highs = days.map(\.high)

        let gradient = await WeatherAtmosphericAdapter.widgetGradient(
            weather: weather, precipSeries: precipSeries, coordinates: coordinates
        )

        return DailyForecastEntry(
            date: .now,
            location: locationName,
            days: days,
            minTemp: lows.min() ?? 0,
            maxTemp: highs.max() ?? 40,
            backgroundGradient: gradient,
            cityID: cityID,
            staleNote: staleText(fetchedAt, at: .now, timeZone: weather.locationTimeZone)
        )
    }

    static func days(
        from weather: Operations.getForecast.Output.Ok.Body.jsonPayload,
        count: Int,
        labelsToday: Bool = true
    ) -> [DayForecast] {
        let daily = weather.daily
        let timeZone = weather.locationTimeZone
        let times: [Double]? = daily?.time
        let mins: [Double]? = daily?.temperature_2m_min
        let maxs: [Double]? = daily?.temperature_2m_max
        let codes: [Double]? = daily?.weathercode
        let probabilities: [Double?]? = daily?.precipitation_probability_max
        let sums: [Double]? = daily?.precipitation_sum
        guard let firstDay = weather.dayIndex(at: .now) else { return [] }
        let dayCount = min(times?.count ?? 0, firstDay + count)

        var days: [DayForecast] = []
        for index in firstDay..<dayCount {
            guard let low = Self.value(mins, index), let high = Self.value(maxs, index) else { continue }
            let weekday = Self.weekdayLabel(
                timestamp: Self.value(times, index) ?? 0,
                timeZone: timeZone,
                isToday: labelsToday && index == firstDay
            )
            let icon = WeatherSymbol.sfSymbol(weathercode: Self.value(codes, index) ?? 0)
            var probability: Double?
            if let probabilities, probabilities.indices.contains(index) {
                probability = probabilities[index]
            }
            let sum: Double? = Self.value(sums, index)
            let day = DayForecast(
                id: index,
                weekday: weekday,
                icon: icon,
                precipProbability: probability,
                precipSum: sum,
                low: low,
                high: high
            )
            days.append(day)
        }
        return days
    }

    private static func value(_ array: [Double]?, _ index: Int) -> Double? {
        guard let array, array.indices.contains(index) else { return nil }
        return array[index]
    }

    private static func weekdayLabel(timestamp: Double, timeZone: TimeZone, isToday: Bool) -> String {
        if isToday { return String(localized: "Heute") }
        let style = Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated)
        return Date(timeIntervalSince1970: timestamp).formatted(style)
    }
}
