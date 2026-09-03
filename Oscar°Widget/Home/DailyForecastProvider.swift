import CoreLocation
import Foundation
import WidgetKit

struct DailyForecastProvider: AppIntentTimelineProvider {
    private let client = APIClient.shared

    func placeholder(in context: Context) -> DailyForecastEntry {
        .placeholder
    }

    func snapshot(for configuration: SelectCityIntent, in context: Context) async -> DailyForecastEntry {
        context.isPreview ? placeholder(in: context) : await makeEntry(for: configuration)
    }

    func timeline(for configuration: SelectCityIntent, in context: Context) async -> Timeline<DailyForecastEntry> {
        // Always emit an entry for the resolved location — never an empty timeline, which would
        // make WidgetKit keep the *previous* location's entry on screen after a config change.
        let entry = await makeEntry(for: configuration)
        let nextRefresh: TimeInterval = entry.days.isEmpty ? 15 * 60 : 60 * 60
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(nextRefresh)))
    }

    private func makeEntry(for configuration: SelectCityIntent) async -> DailyForecastEntry {
        let resolved = await resolveLocation(configuration.city)
        do {
            return try await forecastEntry(coordinates: resolved.coordinates, locationName: resolved.name)
        } catch {
            return .unavailable(location: resolved.name)
        }
    }

    private func forecastEntry(
        coordinates: CLLocationCoordinate2D,
        locationName: String
    ) async throws -> DailyForecastEntry {
        async let weatherRequest = client.getForecast(
            coordinates: coordinates,
            forecastDays: ._14,
            hourly: [
                .weathercode, .cloudcover, .relativehumidity_2m, .pressure_msl,
                .precipitation, .snowfall, .windspeed_10m, .winddirection_10m,
            ]
        )
        async let radarRequest = client.getRadarSeries(coordinates: coordinates)

        let weather = try await weatherRequest
        let precipSeries = try? await radarRequest

        let daily = weather.daily
        let timeZone = weather.locationTimeZone
        let times: [Double]? = daily?.time
        let mins: [Double]? = daily?.temperature_2m_min
        let maxs: [Double]? = daily?.temperature_2m_max
        let codes: [Double]? = daily?.weathercode
        // Open-Meteo types this one field as an array of *optional* doubles.
        let probabilities: [Double?]? = daily?.precipitation_probability_max
        let sums: [Double]? = daily?.precipitation_sum
        let dayCount = min(times?.count ?? 0, 9)

        var days: [DayForecast] = []
        for index in 0..<dayCount {
            guard let low = value(mins, index), let high = value(maxs, index) else { continue }
            let weekday = Self.weekdayLabel(
                timestamp: value(times, index) ?? 0,
                timeZone: timeZone,
                isToday: index == 0
            )
            let icon = WeatherSymbol.sfSymbol(weathercode: value(codes, index) ?? 0)
            var probability: Double?
            if let probabilities, probabilities.indices.contains(index) {
                probability = probabilities[index]
            }
            let sum: Double? = value(sums, index)
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

        let lows = days.map(\.low)
        let highs = days.map(\.high)

        let dayBegin = weather.hourly?.time.first ?? 0
        let gradient = await MainActor.run {
            let weatherForRendering = Weather()
            weatherForRendering.time = (Date.now.timeIntervalSince1970 - Double(dayBegin)) / 86400.0
            weatherForRendering.forecast = weather
            weatherForRendering.precipSeries = precipSeries
            return WeatherAtmosphericAdapter().getWidgetFullGradient(
                from: weatherForRendering, at: coordinates)
        }

        return DailyForecastEntry(
            date: .now,
            location: locationName,
            days: days,
            minTemp: lows.min() ?? 0,
            maxTemp: highs.max() ?? 40,
            temperatureUnit: weather.daily_units?.temperature_2m_min ?? "°C",
            precipitationUnit: weather.daily_units?.precipitation_sum ?? "mm",
            backgroundGradient: gradient
        )
    }

    private func resolveLocation(_ cityID: String?) async
        -> (coordinates: CLLocationCoordinate2D, name: String)
    {
        if let cityID,
           let city = WidgetCity(id: cityID),
           !city.isCurrentLocation,
           city.latitude.isFinite,
           city.longitude.isFinite {
            return (
                CLLocationCoordinate2D(
                    latitude: city.latitude,
                    longitude: city.longitude
                ),
                city.name
            )
        }
        return await Task { @MainActor in
            LocationService.shared.update()
            let coordinate = LocationService.shared.getCoordinates()
            let name = await LocationService.shared.getLocationName()
            return (coordinates: coordinate, name: name)
        }.value
    }

    private func value(_ array: [Double]?, _ index: Int) -> Double? {
        guard let array, array.indices.contains(index) else { return nil }
        return array[index]
    }

    private static func weekdayLabel(timestamp: Double, timeZone: TimeZone, isToday: Bool) -> String {
        if isToday { return String(localized: "Heute") }
        let style = Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated)
        return Date(timeIntervalSince1970: timestamp).formatted(style)
    }
}
