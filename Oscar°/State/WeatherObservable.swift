//
//  WeatherObservable.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.01.24.
//

import CoreLocation
import Foundation
import SwiftUI

enum WeatherLoadingQuery: String, CaseIterable, Comparable {
    case forecast
    case airQuality
    case rainRadar
    case alerts

    var displayName: String {
        switch self {
        case .forecast:
            return "Forecast"
        case .airQuality:
            return "Air quality"
        case .rainRadar:
            return "Rain radar"
        case .alerts:
            return "Alerts"
        }
    }

    static func < (lhs: WeatherLoadingQuery, rhs: WeatherLoadingQuery) -> Bool {
        let lhsIndex = allCases.firstIndex(of: lhs) ?? allCases.endIndex
        let rhsIndex = allCases.firstIndex(of: rhs) ?? allCases.endIndex
        return lhsIndex < rhsIndex
    }
}

enum WeatherLoadState {
    case idle
    case loading
    case loaded
    case failed
}

@MainActor
@Observable
final class Weather {
    var isLoading: Bool = false
    var loadState: WeatherLoadState = .idle
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var refreshRequestedWhileBusy = false
    var loadingQueries: Set<WeatherLoadingQuery> = []
    var forecast: Operations.getForecast.Output.Ok.Body.jsonPayload
    var alerts: AlertResponse
    var air: Operations.getAirQuality.Output.Ok.Body.jsonPayload
    var time: Double
    var precipSeries: PrecipSeriesResponse?
    var cloudSeries: CloudSeriesResponse?
    var stations: [Components.Schemas.NearbyStation] = []
    var error: String = ""
    var lastUpdated: Date?
    var debug = false

    var hasContent: Bool {
        lastUpdated != nil
    }
    
    init() {
        time = 0
        forecast = Operations.getForecast.Output.Ok.Body.jsonPayload.init(
            latitude: 0.0,
            longitude: 0.0,
            current: .init(cloudcover: 0.0, time: 0.0, temperature: 20.0, windspeed: 0.0, wind_direction_10m: 0.0, weathercode: 0.0)
        )
        alerts = .oscar(.empty)
        air = Operations.getAirQuality.Output.Ok.Body.jsonPayload.init(latitude: 0, longitude: 0, hourly: nil)
        precipSeries = nil
    }
    
    func updateTime() {
        let dayBegin = self.forecast.hourly?.time.first ?? 0
        self.time = (Date.now.timeIntervalSince1970-dayBegin)/86400.0
    }

    func markLoading(_ query: WeatherLoadingQuery) {
        loadingQueries.insert(query)
    }

    func markFinished(_ query: WeatherLoadingQuery) {
        loadingQueries.remove(query)
    }

    func clearLoadingQueries() {
        loadingQueries.removeAll()
    }
}

extension Weather {
    private enum RadarOutcome {
        case fetched(PrecipSeriesResponse?)
        case failed
    }

    private enum CloudOutcome {
        case fetched(CloudSeriesResponse?)
        case failed
    }

    private enum UpdateResponse {
        case forecast(Operations.getForecast.Output.Ok.Body.jsonPayload)
        case airQuality(Operations.getAirQuality.Output.Ok.Body.jsonPayload)
        case precipSeries(RadarOutcome)
        case cloudSeries(CloudOutcome)
    }

    func refresh(
        location: Location,
        client: APIClient = .shared,
        locationService: LocationService = .shared
    ) async {
        guard !isRefreshing else {
            refreshRequestedWhileBusy = true
            return
        }
        isRefreshing = true
        defer {
            if refreshRequestedWhileBusy {
                refreshRequestedWhileBusy = false
                Task { await refresh(location: location, client: client, locationService: locationService) }
            }
        }
        isLoading = true
        error = ""
        if loadState == .idle { loadState = .loading }
        clearLoadingQueries()
        defer {
            isRefreshing = false
            isLoading = false
            clearLoadingQueries()
        }

        locationService.update()
        let info = await locationService.getPlacemarkInfo()
        location.coordinates = locationService.getCoordinates()
        if !info.name.isEmpty || location.name.isEmpty {
            location.name = info.name
        }
        location.countryCode = info.countryCode

        let coordinates = location.coordinates

        do {
            var forecastResponse: Operations.getForecast.Output.Ok.Body.jsonPayload?
            var airQualityResponse: Operations.getAirQuality.Output.Ok.Body.jsonPayload?
            var radarOutcome: RadarOutcome = .failed
            var cloudOutcome: CloudOutcome = .failed

            try await withThrowingTaskGroup(of: UpdateResponse.self) { group in
                markLoading(.forecast)
                group.addTask {
                    .forecast(try await client.getForecast(coordinates: coordinates))
                }

                markLoading(.airQuality)
                group.addTask {
                    .airQuality(try await client.getAirQuality(coordinates: coordinates))
                }

                markLoading(.rainRadar)
                group.addTask {
                    do { return .precipSeries(.fetched(try await client.getRadarSeries(coordinates: coordinates))) }
                    catch { return .precipSeries(.failed) }
                }

                group.addTask {
                    do { return .cloudSeries(.fetched(try await client.getCloudSeries(coordinates: coordinates))) }
                    catch { return .cloudSeries(.failed) }
                }

                for try await response in group {
                    switch response {
                    case .forecast(let response):
                        forecastResponse = response
                        markFinished(.forecast)
                    case .airQuality(let response):
                        airQualityResponse = response
                        markFinished(.airQuality)
                    case .precipSeries(let outcome):
                        radarOutcome = outcome
                        markFinished(.rainRadar)
                    case .cloudSeries(let outcome):
                        cloudOutcome = outcome
                    }
                }
            }

            guard let forecastResponse, let airQualityResponse else {
                throw URLError(.badServerResponse)
            }

            forecast = forecastResponse
            air = airQualityResponse
            if case .fetched(let value) = radarOutcome {
                precipSeries = value
            }
            if case .fetched(let value) = cloudOutcome {
                cloudSeries = value
            }
            updateTime()
            lastUpdated = .now
            loadState = .loaded
            isLoading = false

            if locationService.knownCoordinates() != nil {
                let snapshot = WeatherSnapshot(
                    forecast: forecastResponse,
                    air: airQualityResponse,
                    precipSeries: precipSeries,
                    coordinates: CodableCoordinate(LocationService.outboundCoordinate(coordinates)),
                    locationName: location.name,
                    savedAt: lastUpdated ?? .now
                )
                Task.detached {
                    WeatherSnapshotStore.save(snapshot)
                }
            }

            markLoading(.alerts)
            do {
                alerts = try await client.getAlerts(
                    coordinates: coordinates,
                    countryCode: location.countryCode
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                alerts = .oscar(.empty)
            }
            markFinished(.alerts)

            do {
                stations = try await client.getNearbyStations(coordinates: coordinates)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                stations = []
            }
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
            if !hasContent { loadState = .failed }
        }
    }

    func apply(snapshot: WeatherSnapshot, location: Location) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            forecast = snapshot.forecast
            air = snapshot.air
            precipSeries = snapshot.precipSeries
            updateTime()
            lastUpdated = snapshot.savedAt
            location.coordinates = snapshot.coordinates.coordinate
            location.name = snapshot.locationName
        }
        loadState = .loaded
    }

    static var mock: Weather {
        let mockWeather = Weather()
        
        let hourlyTimeInterval: TimeInterval = 3600
        let hourlyStartTime = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        let hourlyTimes = (0..<36).map { hourlyStartTime + Double($0) * hourlyTimeInterval }
        
        mockWeather.forecast = Operations.getForecast.Output.Ok.Body.jsonPayload(
            latitude: 51.34,
            longitude: 12.379999,
            elevation: 109.0,
            generationtime_ms: 1.9611120223999023,
            utc_offset_seconds: 7200,
            timezone_abbreviation: "CEST",
            hourly: Operations.getForecast.Output.Ok.Body.jsonPayload.hourlyPayload(
                time: hourlyTimes,
                temperature_2m: (0..<36).map { 22 - 6 * cos(Double($0 - 2) / 24 * 2 * .pi) },
                relativehumidity_2m: (0..<36).map { 70.0 + Double($0 % 12) },
                apparent_temperature: (0..<36).map { 21 - 6 * cos(Double($0 - 2) / 24 * 2 * .pi) },
                pressure_msl: (0..<36).map { _ in 1019.0 + Double.random(in: -1...1) },
                cloudcover: (0..<36).map { _ in Double.random(in: 0...100) },
                windspeed_10m: (0..<36).map { _ in Double.random(in: 5...15) },
                winddirection_10m: (0..<36).map { _ in Double.random(in: 0...360) },
                precipitation: (0..<36).map { _ in Double.random(in: 0...0.5) },
                weathercode: (0..<36).map { _ in Double(Int.random(in: 0...3)) },
                is_day: (0..<36).map { $0 % 24 < 16 ? 1.0 : 0.0 }
            ),
            daily: Components.Schemas.DailyResponse(
                time: (0..<12).map { hourlyStartTime + Double($0 * 86400) },
                temperature_2m_max: [28.0, 29.5, 27.8, 26.3, 30.1, 24.6, 22.9, 25.4, 27.2, 28.8, 26.1, 23.7],
                temperature_2m_min: [14.8, 16.2, 15.5, 13.9, 17.3, 15.1, 12.8, 13.6, 15.9, 16.4, 14.2, 12.5],
                precipitation_sum: [0.0, 2.5, 0.8, 0.0, 5.2, 7.4, 1.1, 0.0, 0.0, 0.3, 3.9, 6.0],
                precipitation_probability_max: [0, 30, 20, 10, 60, 80, 35, 5, 0, 15, 55, 70],
                weathercode: [2.0, 3.0, 1.0, 0.0, 3.0, 61.0, 2.0, 0.0, 1.0, 2.0, 61.0, 63.0],
                sunrise: (0..<12).map { hourlyStartTime + 21600 + Double($0 * 86400) },
                sunset: (0..<12).map { hourlyStartTime + 64800 + Double($0 * 86400) }
            ),
            current: Components.Schemas.CurrentWeather(
                cloudcover: 45.0,
                time: hourlyStartTime,
                temperature: 22.5,
                windspeed: 10.0,
                wind_direction_10m: 180.0,
                weathercode: 1.0,
                precipitation: 0.0,
                is_day: 1.0
            )
        )
        
        mockWeather.time = 0.5
        mockWeather.alerts = .oscar(.empty)
        mockWeather.air = Operations.getAirQuality.Output.Ok.Body.jsonPayload(latitude: 51.34, longitude: 12.379999, hourly: nil)
        mockWeather.precipSeries = nil

        return mockWeather
    }
}
