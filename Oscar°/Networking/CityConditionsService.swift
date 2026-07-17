//
//  CityConditionsService.swift
//  Oscar°
//
//  Batch current conditions for the locations list: one Open-Meteo request
//  carrying every saved coordinate (comma-separated latitude/longitude lists),
//  mapped into per-card display data plus an AtmosphereSnapshot so each card
//  can render the same sky the full simulation would.
//

import CoreLocation
import Foundation
import SwiftUI

/// Current conditions of one saved location, ready for a list card.
struct CityConditions {
    let temperature: Double
    let weathercode: Int
    let isDay: Bool
    /// Radar sees rain at the location right now (may disagree with the forecast).
    let isRadarRaining: Bool
    /// Sky state for the card's static sim backdrop.
    let snapshot: AtmosphereSnapshot

    /// Derived from the snapshot's condition family, not the raw weathercode:
    /// the mapper lifts a dry forecast to rain when radar measures precipitation,
    /// and the label must agree with the sky the card shows.
    var conditionText: String {
        WeatherConditionLabel.text(for: snapshot.condition)
    }

    /// The app's own weather icon asset (01d…50n) for the map chip, radar-aware
    /// like the widget's icon: measured rain over a dry forecast code shows the
    /// rain icon.
    var iconAssetName: String {
        if isRadarRaining, ![51...57, 61...67, 71...77, 80...86, 95...99].contains(where: { $0.contains(weathercode) }) {
            return isDay ? "10d" : "10n"
        }
        return HourlyFormatting.weatherIconName(weatherCode: Double(weathercode), isDay: isDay ? 1 : 0)
    }
}

/// Weather-code families as short labels (the app-side mirror of the watch's
/// condition line).
enum WeatherConditionLabel {
    static func text(for code: Int) -> String {
        switch code {
        case 0, 1:
            return String(localized: "Klar")
        case 2:
            return String(localized: "Teils bewölkt")
        case 3:
            return String(localized: "Bedeckt")
        case 45, 48:
            return String(localized: "Nebel")
        case 51...57:
            return String(localized: "Nieselregen")
        case 61...65:
            return String(localized: "Regen")
        case 66, 67:
            return String(localized: "Gefrierender Regen")
        case 71...77, 85, 86:
            return String(localized: "Schneefall")
        case 80...82:
            return String(localized: "Schauer")
        case 95...99:
            return String(localized: "Gewitter")
        default:
            return String(localized: "Bewölkt")
        }
    }

    /// Label for an already-derived condition family (the mapper may have
    /// upgraded a dry code to rain based on radar).
    static func text(for family: AtmosphereConditionFamily) -> String {
        switch family {
        case .clear:
            String(localized: "Klar")
        case .partlyCloudy:
            String(localized: "Teils bewölkt")
        case .overcast:
            String(localized: "Bedeckt")
        case .fog:
            String(localized: "Nebel")
        case .drizzle:
            String(localized: "Nieselregen")
        case .rain:
            String(localized: "Regen")
        case .freezingRain:
            String(localized: "Gefrierender Regen")
        case .snow:
            String(localized: "Schneefall")
        case .showers:
            String(localized: "Schauer")
        case .thunderstorm:
            String(localized: "Gewitter")
        }
    }

}

@MainActor
@Observable
final class CityConditionsStore {
    /// Shared so re-presenting the locations sheet reuses the last fetch
    /// instead of flashing placeholders on every open.
    static let shared = CityConditionsStore()

    private(set) var conditions: [String: CityConditions] = [:]
    private(set) var isLoading = false
    private var lastFetch: (keys: Set<String>, at: Date)?

    func conditions(for coordinate: CLLocationCoordinate2D) -> CityConditions? {
        conditions[Self.key(for: coordinate)]
    }

    /// One request for all coordinates. Throttled: a coordinate set already
    /// covered by a fetch within 5 minutes is a no-op unless forced — reorders
    /// keep the same key set and deletions shrink it, so neither refetches.
    func refresh(coordinates: [CLLocationCoordinate2D], force: Bool = false) async {
        let outbound = coordinates.map(LocationService.outboundCoordinate)
        guard !outbound.isEmpty else { return }

        let fetchKeys = Set(outbound.map(Self.key(for:)))
        if !force,
           let lastFetch,
           fetchKeys.isSubset(of: lastFetch.keys),
           Date.now.timeIntervalSince(lastFetch.at) < 5 * 60 {
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // Radar runs alongside the forecast batch: nowcast rain that the
            // forecast doesn't see yet must reach the cards too. Best-effort —
            // a missing series just means "no radar" for that place.
            async let radarTask = Self.fetchRadar(coordinates: outbound)
            let entries = try await Self.fetchBatch(coordinates: outbound)
            let radarByKey = await radarTask
            // Rebuild from the requested set only, so entries for deleted
            // cities don't accumulate over the session.
            var updated = conditions.filter { fetchKeys.contains($0.key) }
            // Open-Meteo answers in request order; zip against what was asked
            // so grid-snapped response coordinates can't break the mapping.
            for (requested, entry) in zip(outbound, entries) {
                let key = Self.key(for: requested)
                updated[key] = Self.makeConditions(
                    entry: entry,
                    coordinate: requested,
                    radar: radarByKey[key]
                )
            }
            conditions = updated
            lastFetch = (fetchKeys, .now)
        } catch is CancellationError {
            return
        } catch {
            // Cards keep showing their previous conditions (or placeholders);
            // the next sheet presentation retries.
            return
        }
    }

    /// One radar series per coordinate, fetched concurrently. Failures and
    /// "no coverage" both collapse to a missing entry.
    private static func fetchRadar(
        coordinates: [CLLocationCoordinate2D]
    ) async -> [String: PrecipSeriesResponse] {
        await withTaskGroup(of: (String, PrecipSeriesResponse?).self) { group in
            for coordinate in coordinates {
                group.addTask {
                    let series = try? await APIClient.shared.getRadarSeries(coordinates: coordinate)
                    return (Self.key(for: coordinate), series ?? nil)
                }
            }
            var result: [String: PrecipSeriesResponse] = [:]
            for await (key, series) in group {
                if let series {
                    result[key] = series
                }
            }
            return result
        }
    }

    nonisolated private static func key(for coordinate: CLLocationCoordinate2D) -> String {
        let rounded = LocationService.outboundCoordinate(coordinate)
        return "\(rounded.latitude),\(rounded.longitude)"
    }

    /// Builds the card snapshot through the real weather→sky mapper by wrapping
    /// the batched current conditions in a minimal forecast payload, so cards and
    /// the full simulation always agree on how a sky looks.
    private static func makeConditions(
        entry: BatchCurrentEntry,
        coordinate: CLLocationCoordinate2D,
        radar: PrecipSeriesResponse?
    ) -> CityConditions? {
        guard let current = entry.current else { return nil }

        let shell = Weather()
        // The mapper reads the radar rate at "now" and lifts a dry forecast to
        // a rainy scene when the measurement disagrees — same as the main sim.
        shell.precipSeries = radar
        shell.forecast = .init(
            latitude: entry.latitude,
            longitude: entry.longitude,
            utc_offset_seconds: entry.utc_offset_seconds,
            // The mapper reads humidity and pressure only from hourly arrays;
            // a one-element hour carries the batched current values so the card
            // sky gets the same haze/turbidity inputs as the full simulation
            // (which otherwise default to 50% humidity and standard pressure).
            hourly: .init(
                time: [current.time],
                relativehumidity_2m: current.relativehumidity_2m.map { [$0] },
                pressure_msl: current.pressure_msl.map { [$0] }
            ),
            current: .init(
                cloudcover: current.cloudcover ?? 0,
                time: current.time,
                temperature: current.temperature ?? 0,
                windspeed: current.windspeed ?? 0,
                wind_direction_10m: current.wind_direction_10m ?? 0,
                weathercode: current.weathercode ?? 0,
                precipitation: current.precipitation,
                is_day: current.is_day
            )
        )
        let snapshot = AtmosphereWeatherMapper.snapshot(from: shell, at: coordinate)

        guard let temperature = current.temperature else { return nil }
        return CityConditions(
            temperature: temperature,
            weathercode: Int(current.weathercode ?? 0),
            isDay: current.is_day == 1,
            isRadarRaining: radar?.isRaining() ?? false,
            snapshot: snapshot
        )
    }

    private static func fetchBatch(
        coordinates: [CLLocationCoordinate2D]
    ) async throws -> [BatchCurrentEntry] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: coordinates.map { String($0.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: coordinates.map { String($0.longitude) }.joined(separator: ",")),
            URLQueryItem(
                name: "current",
                value: "temperature,weathercode,cloudcover,windspeed,wind_direction_10m,precipitation,is_day,"
                    + "relativehumidity_2m,pressure_msl"
            ),
            URLQueryItem(name: "temperature_unit", value: SettingService.resolvedTemperatureUnit),
            URLQueryItem(
                name: "windspeed_unit",
                value: WindSpeedUnit(settingValue: SettingService.resolvedWindSpeedUnit).apiRawValue
            ),
            URLQueryItem(name: "precipitation_unit", value: SettingService.resolvedPrecipitationUnit),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.addAPIContactIdentity()
        let (data, http) = try await APIClient.fetchWithRetry(request)
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }

        // One coordinate answers with a single object, several with an array.
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([BatchCurrentEntry].self, from: data) {
            return list
        }
        return [try decoder.decode(BatchCurrentEntry.self, from: data)]
    }
}

/// Response shape of the batched request (field names match the requested
/// legacy parameter names the rest of the app uses).
private struct BatchCurrentEntry: Decodable {
    struct Current: Decodable {
        let time: Double
        let temperature: Double?
        let weathercode: Double?
        let cloudcover: Double?
        let windspeed: Double?
        let wind_direction_10m: Double?
        let precipitation: Double?
        let is_day: Double?
        let relativehumidity_2m: Double?
        let pressure_msl: Double?
    }

    let latitude: Double
    let longitude: Double
    let utc_offset_seconds: Int?
    let current: Current?
}
