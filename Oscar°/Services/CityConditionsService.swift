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

struct CityConditions {
    let temperature: Double
    let weathercode: Int
    let isDay: Bool
    let isRadarRaining: Bool
    let snapshot: AtmosphereSnapshot

    var conditionText: String {
        WeatherConditionLabel.text(for: snapshot.condition)
    }

    var iconAssetName: String {
        if isRadarRaining, ![51...57, 61...67, 71...77, 80...86, 95...99].contains(where: { $0.contains(weathercode) }) {
            return isDay ? "10d" : "10n"
        }
        return HourlyFormatting.weatherIconName(weatherCode: Double(weathercode), isDay: isDay ? 1 : 0)
    }
}

@MainActor
@Observable
final class CityConditionsStore {
    static let shared = CityConditionsStore()

    private(set) var conditions: [String: CityConditions] = [:]
    private(set) var isLoading = false
    private var lastFetch: (keys: Set<String>, at: Date)?

    func conditions(for coordinate: CLLocationCoordinate2D) -> CityConditions? {
        conditions[Self.key(for: coordinate)]
    }

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
            async let radarTask = Self.fetchRadar(coordinates: outbound)
            let entries = try await Self.fetchBatch(coordinates: outbound)
            let radarByKey = await radarTask
            var updated = conditions.filter { fetchKeys.contains($0.key) }
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
            return
        }
    }

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

    private static func makeConditions(
        entry: BatchCurrentEntry,
        coordinate: CLLocationCoordinate2D,
        radar: PrecipSeriesResponse?
    ) -> CityConditions? {
        guard let current = entry.current else { return nil }

        let shell = Weather()
        shell.precipSeries = radar
        shell.forecast = .init(
            latitude: entry.latitude,
            longitude: entry.longitude,
            utc_offset_seconds: entry.utc_offset_seconds,
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
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.addAPIContactIdentity()
        let (data, http) = try await APIClient.fetchWithRetry(request)
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }

        let decoder = JSONDecoder()
        if let list = try? decoder.decode([BatchCurrentEntry].self, from: data) {
            return list
        }
        return [try decoder.decode(BatchCurrentEntry.self, from: data)]
    }
}

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
