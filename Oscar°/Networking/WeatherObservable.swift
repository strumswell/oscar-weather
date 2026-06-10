//
//  WeatherObservable.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.01.24.
//

import Foundation

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

@Observable
class Weather {
    var isLoading: Bool = false
    var loadingQueries: Set<WeatherLoadingQuery> = []
    var forecast: Operations.getForecast.Output.Ok.Body.jsonPayload
    var alerts: AlertResponse
    var air: Operations.getAirQuality.Output.Ok.Body.jsonPayload
    var time: Double
    var radar: Components.Schemas.RadarResponse
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
        alerts = .brightsky(.init())
        air = Operations.getAirQuality.Output.Ok.Body.jsonPayload.init(latitude: 0, longitude: 0, hourly: nil)
        radar = .init()
    }
    
    // Update internal clock used for day simulation background
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
    private enum UpdateResponse {
        case forecast(Operations.getForecast.Output.Ok.Body.jsonPayload)
        case airQuality(Operations.getAirQuality.Output.Ok.Body.jsonPayload)
        case radar(Components.Schemas.RadarResponse)
    }

    @MainActor
    func refresh(
        location: Location,
        client: APIClient = .shared,
        locationService: LocationService = .shared
    ) async {
        guard !isLoading else { return }
        isLoading = true
        error = ""
        clearLoadingQueries()
        defer {
            isLoading = false
            clearLoadingQueries()
        }

        locationService.update()
        let info = await locationService.getPlacemarkInfo()
        location.coordinates = locationService.getCoordinates()
        location.name = info.name
        location.countryCode = info.countryCode

        let coordinates = location.coordinates

        do {
            var forecastResponse: Operations.getForecast.Output.Ok.Body.jsonPayload?
            var airQualityResponse: Operations.getAirQuality.Output.Ok.Body.jsonPayload?
            var radarResponse: Components.Schemas.RadarResponse?

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
                    .radar(try await client.getRainRadar(coordinates: coordinates))
                }

                for try await response in group {
                    switch response {
                    case .forecast(let response):
                        forecastResponse = response
                        markFinished(.forecast)
                    case .airQuality(let response):
                        airQualityResponse = response
                        markFinished(.airQuality)
                    case .radar(let response):
                        radarResponse = response
                        markFinished(.rainRadar)
                    }
                }
            }

            guard let forecastResponse, let airQualityResponse, let radarResponse else {
                throw URLError(.badServerResponse)
            }

            forecast = forecastResponse
            air = airQualityResponse
            radar = radarResponse
            updateTime()
            lastUpdated = .now
            isLoading = false

            let snapshot = WeatherSnapshot(
                forecast: forecastResponse,
                air: airQualityResponse,
                radar: radarResponse,
                coordinates: CodableCoordinate(coordinates),
                locationName: location.name,
                savedAt: lastUpdated ?? .now
            )
            Task.detached {
                WeatherSnapshotStore.save(snapshot)
            }

            markLoading(.alerts)
            alerts = try await client.getAlerts(
                coordinates: coordinates,
                countryCode: location.countryCode
            )
            markFinished(.alerts)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    func apply(snapshot: WeatherSnapshot, location: Location) {
        forecast = snapshot.forecast
        air = snapshot.air
        radar = snapshot.radar
        updateTime()
        lastUpdated = snapshot.savedAt
        location.coordinates = snapshot.coordinates.coordinate
        location.name = snapshot.locationName
    }

    static var mock: Weather {
        let mockWeather = Weather()
        
        // Generate 36 hours of mock hourly data
        let hourlyTimeInterval: TimeInterval = 3600 // 1 hour
        let hourlyStartTime = 1719266400.0
        let hourlyTimes = (0..<36).map { hourlyStartTime + Double($0) * hourlyTimeInterval }
        
        // Mock forecast data
        mockWeather.forecast = Operations.getForecast.Output.Ok.Body.jsonPayload(
            latitude: 51.34,
            longitude: 12.379999,
            elevation: 109.0,
            generationtime_ms: 1.9611120223999023,
            utc_offset_seconds: 7200,
            timezone_abbreviation: "CEST",
            hourly: Operations.getForecast.Output.Ok.Body.jsonPayload.hourlyPayload(
                time: hourlyTimes,
                temperature_2m: (0..<36).map { 18.0 + Double($0 % 24) / 2 }, // Temperature variation
                relativehumidity_2m: (0..<36).map { 70.0 + Double($0 % 12) }, // Humidity variation
                apparent_temperature: (0..<36).map { 17.0 + Double($0 % 24) / 2 }, // Apparent temperature variation
                pressure_msl: (0..<36).map { _ in 1019.0 + Double.random(in: -1...1) }, // Slight pressure variation
                cloudcover: (0..<36).map { _ in Double.random(in: 0...100) }, // Random cloud cover
                windspeed_10m: (0..<36).map { _ in Double.random(in: 5...15) }, // Random wind speed
                winddirection_10m: (0..<36).map { _ in Double.random(in: 0...360) }, // Random wind direction
                precipitation: (0..<36).map { _ in Double.random(in: 0...0.5) }, // Random light precipitation
                weathercode: (0..<36).map { _ in Double(Int.random(in: 0...3)) }, // Random weather codes
                is_day: (0..<36).map { $0 % 24 < 16 ? 1.0 : 0.0 } // Day time between 6am and 10pm
            ),
            daily: Components.Schemas.DailyResponse(
                time: (0..<5).map { hourlyStartTime + Double($0 * 86400) },
                temperature_2m_max: [28.0, 29.5, 27.8, 26.3, 30.1],
                temperature_2m_min: [14.8, 16.2, 15.5, 13.9, 17.3],
                precipitation_sum: [0.0, 2.5, 0.8, 0.0, 5.2],
                precipitation_probability_max: [0, 30, 20, 10, 60],
                weathercode: [2.0, 3.0, 1.0, 0.0, 3.0],
                sunrise: (0..<5).map { hourlyStartTime + 21600 + Double($0 * 86400) }, // Sunrise at 6 AM each day
                sunset: (0..<5).map { hourlyStartTime + 64800 + Double($0 * 86400) }  // Sunset at 6 PM each day
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
        
        // Set other properties
        mockWeather.time = 0.5 // Midday
        mockWeather.alerts = .brightsky(.init()) // Empty alerts
        mockWeather.air = Operations.getAirQuality.Output.Ok.Body.jsonPayload(latitude: 51.34, longitude: 12.379999, hourly: nil)
        mockWeather.radar = .init() // Empty radar
        
        return mockWeather
    }
}
