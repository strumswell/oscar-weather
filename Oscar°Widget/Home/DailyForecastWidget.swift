//
//  DailyForecastWidget.swift
//  Oscar°WidgetExtension
//
//  Multi-day forecast widget (medium / large) with a configurable city and the
//  atmospheric sky gradient used by the Now widget.
//

import AppIntents
import CoreData
import CoreLocation
import SwiftUI
import WidgetKit

// MARK: - Configurable city

struct WidgetCity: AppEntity, Identifiable {
    static let currentLocationID = "__current__"

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Ort")
    }
    static let defaultQuery = WidgetCityQuery()

    var id: String
    var name: String
    var latitude: Double
    var longitude: Double

    var isCurrentLocation: Bool { id == Self.currentLocationID }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: isCurrentLocation ? "location.fill" : "mappin")
        )
    }

    static var currentLocation: WidgetCity {
        WidgetCity(
            id: currentLocationID,
            name: String(localized: "Aktueller Standort"),
            latitude: .nan,
            longitude: .nan
        )
    }
}

struct WidgetCityQuery: EntityQuery {
    func entities(for identifiers: [WidgetCity.ID]) async throws -> [WidgetCity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetCity] {
        [.currentLocation] + WidgetCityStore.savedCities()
    }

    func defaultResult() async -> WidgetCity? { .currentLocation }
}

/// Reads the saved cities from the Core Data store shared via the app group.
enum WidgetCityStore {
    static func savedCities() -> [WidgetCity] {
        let context = PersistenceController.shared.container.viewContext
        return context.performAndWait {
            let request: NSFetchRequest<City> = City.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
            guard let results = try? context.fetch(request) else { return [] }
            return results.compactMap { city in
                guard let label = city.label else { return nil }
                return WidgetCity(
                    id: "\(city.lat),\(city.lon)",
                    name: label,
                    latitude: city.lat,
                    longitude: city.lon
                )
            }
        }
    }
}

struct SelectCityIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Ort wählen"
    static let description = IntentDescription("Wähle den Ort für die Tagesvorhersage.")

    @Parameter(title: "Ort")
    var city: WidgetCity?
}

// MARK: - Weather symbol mapping

enum WeatherSymbol {
    static func sfSymbol(weathercode: Double, isDay: Bool = true) -> String {
        switch weathercode {
        case 0, 1: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 80, 81: return "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

// MARK: - Timeline entry

struct DayForecast: Identifiable {
    let id: Int
    let weekday: String
    let icon: String
    let precipProbability: Double?
    let precipSum: Double?
    let low: Double
    let high: Double
}

struct DailyForecastEntry: TimelineEntry {
    let date: Date
    let location: String
    let days: [DayForecast]
    let minTemp: Double
    let maxTemp: Double
    let temperatureUnit: String
    let precipitationUnit: String
    let backgroundGradient: LinearGradient

    static var placeholder: DailyForecastEntry {
        let samples: [(String, String, Double, Double, Double?)] = [
            ("Heute", "sun.max.fill", 12, 22, nil),
            ("Di", "cloud.sun.fill", 11, 18, 10),
            ("Mi", "cloud.rain.fill", 13, 24, 60),
            ("Do", "sun.max.fill", 14, 26, nil),
            ("Fr", "sun.max.fill", 14, 25, nil),
            ("Sa", "cloud.sun.fill", 12, 21, 20),
            ("So", "cloud.fill", 11, 19, 30),
        ]
        let days = samples.enumerated().map { index, sample in
            DayForecast(
                id: index,
                weekday: sample.0,
                icon: sample.1,
                precipProbability: sample.4,
                precipSum: nil,
                low: sample.2,
                high: sample.3
            )
        }
        return DailyForecastEntry(
            date: .now,
            location: "Berlin",
            days: days,
            minTemp: 11,
            maxTemp: 26,
            temperatureUnit: "°C",
            precipitationUnit: "mm",
            backgroundGradient: LinearGradient(
                colors: [.sunriseStart, .sunnyDayEnd], startPoint: .top, endPoint: .bottom)
        )
    }
}

// MARK: - Provider

struct DailyForecastProvider: AppIntentTimelineProvider {
    private let client = APIClient.shared

    func placeholder(in context: Context) -> DailyForecastEntry {
        .placeholder
    }

    func snapshot(for configuration: SelectCityIntent, in context: Context) async -> DailyForecastEntry {
        (try? await makeEntry(for: configuration)) ?? .placeholder
    }

    func timeline(for configuration: SelectCityIntent, in context: Context) async -> Timeline<DailyForecastEntry> {
        do {
            let entry = try await makeEntry(for: configuration)
            return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60 * 60)))
        } catch {
            // Keep the last rendered entry on screen and retry shortly; never drop the chain.
            return Timeline(entries: [], policy: .after(.now.addingTimeInterval(15 * 60)))
        }
    }

    private func makeEntry(for configuration: SelectCityIntent) async throws -> DailyForecastEntry {
        let resolved = await resolveLocation(configuration.city)
        let coordinates = resolved.coordinates

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
        let utcOffset = weather.utc_offset_seconds ?? 0
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
                utcOffset: utcOffset,
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
            location: resolved.name,
            days: days,
            minTemp: lows.min() ?? 0,
            maxTemp: highs.max() ?? 40,
            temperatureUnit: weather.daily_units?.temperature_2m_min ?? "°C",
            precipitationUnit: weather.daily_units?.precipitation_sum ?? "mm",
            backgroundGradient: gradient
        )
    }

    private func resolveLocation(_ city: WidgetCity?) async
        -> (coordinates: CLLocationCoordinate2D, name: String)
    {
        if let city, !city.isCurrentLocation, city.latitude.isFinite, city.longitude.isFinite {
            return (
                CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude),
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

    private static func weekdayLabel(timestamp: Double, utcOffset: Int, isToday: Bool) -> String {
        if isToday { return String(localized: "Heute") }
        let timeZone = TimeZone(secondsFromGMT: utcOffset) ?? .current
        let style = Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated)
        return Date(timeIntervalSince1970: timestamp).formatted(style)
    }
}

// MARK: - Views

struct DailyForecastEntryView: View {
    var entry: DailyForecastEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isCompact: Bool { family == .systemSmall }
    private var dayCount: Int { family == .systemLarge ? 9 : 4 }
    private var rowSpacing: CGFloat { family == .systemLarge ? 12 : (isCompact ? 4 : 7) }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            Text(entry.location)
                .font(isCompact ? .subheadline : .headline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.bottom, family == .systemLarge ? 4 : 2)

            ForEach(entry.days.prefix(dayCount)) { day in
                if isCompact {
                    DailyForecastCompactRow(day: day)
                        .frame(maxHeight: .infinity)
                } else {
                    DailyForecastRow(
                        day: day,
                        minTemp: entry.minTemp,
                        maxTemp: entry.maxTemp,
                        temperatureUnit: entry.temperatureUnit
                    )
                    .frame(maxHeight: family == .systemLarge ? .infinity : nil)
                }
            }
        }
        .padding(family == .systemLarge ? 16 : 12)
        .foregroundStyle(.white)
        .widgetAccentable()
        .containerBackground(for: .widget) {
            entry.backgroundGradient
                .opacity(renderingMode == .accented ? 0 : 1)
        }
    }
}

struct DailyForecastRow: View {
    let day: DayForecast
    let minTemp: Double
    let maxTemp: Double
    let temperatureUnit: String

    var body: some View {
        HStack(spacing: 10) {
            Text(day.weekday)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 48, alignment: .leading)

            Image(systemName: day.icon)
                .symbolRenderingMode(.multicolor)
                .font(.body)
                .frame(width: 30, height: 22)

            Text(roundTemperatureString(temperature: day.low))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 34, alignment: .trailing)

            TemperatureRangeView(
                low: day.low,
                high: day.high,
                focusLow: nil,
                focusHigh: nil,
                minTemp: minTemp,
                maxTemp: maxTemp,
                unit: temperatureUnit
            )
            .frame(height: 6)

            Text(roundTemperatureString(temperature: day.high))
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(width: 34, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(day.weekday): \(roundTemperatureString(temperature: day.low)) bis \(roundTemperatureString(temperature: day.high))")
        )
    }
}

/// Compact row for the small widget — no range bar, just weekday · icon · high/low.
struct DailyForecastCompactRow: View {
    let day: DayForecast

    var body: some View {
        HStack(spacing: 6) {
            Text(day.weekday)
                .font(.footnote)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 36, alignment: .leading)

            Image(systemName: day.icon)
                .symbolRenderingMode(.multicolor)
                .font(.footnote)
                .frame(width: 22, height: 16)

            Spacer(minLength: 2)

            Text(roundTemperatureString(temperature: day.high))
                .font(.footnote)
                .fontWeight(.semibold)
                .monospacedDigit()

            Text(roundTemperatureString(temperature: day.low))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(day.weekday): \(roundTemperatureString(temperature: day.low)) bis \(roundTemperatureString(temperature: day.high))")
        )
    }
}

// MARK: - Widget

struct DailyForecastWidget: Widget {
    let kind = "DailyForecastWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectCityIntent.self,
            provider: DailyForecastProvider()
        ) { entry in
            DailyForecastEntryView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName(String(localized: "Tagesvorhersage"))
        .description(String(localized: "Mehrtägige Vorhersage mit Temperaturverlauf."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview("Small", as: .systemSmall) {
    DailyForecastWidget()
} timeline: {
    DailyForecastEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    DailyForecastWidget()
} timeline: {
    DailyForecastEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    DailyForecastWidget()
} timeline: {
    DailyForecastEntry.placeholder
}
