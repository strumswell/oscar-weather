//
//  APIClient.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.01.24.
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import CoreLocation

class APIClient {
    var openMeteo: Client
    var oscar: Client
    var openMeteoAqi: Client
    var openMeteoGeo: Client
    var brightsky: Client
    
    init () {
        openMeteo = APIClient.get(url: try! Servers.server1())
        oscar = APIClient.get(url: try! Servers.server2())
        openMeteoAqi = APIClient.get(url: try! Servers.server3())
        openMeteoGeo = APIClient.get(url: try! Servers.server4())
        brightsky = APIClient.get(url: try! Servers.server5())
    }
    
     class func get(url: URL) -> Client {
        return Client(
            serverURL: url,
            transport: URLSessionTransport(),
            middlewares: [
                RetryingMiddleware(
                    signals: [.code(429), .range(500..<600), .errorThrown],
                    policy: .upToAttempts(count: 3),
                    delay: .constant(seconds: 1)
                )
            ]
        )
    }
    
    func getForecast(coordinates: CLLocationCoordinate2D, forecastDays: Operations.getForecast.Input.Query.forecast_daysPayload? = ._14) async throws -> Operations.getForecast.Output.Ok.Body.jsonPayload {
        let fallbackForecast: Operations.getForecast.Output.Ok.Body.jsonPayload = .init(latitude: coordinates.latitude, longitude: coordinates.longitude, current: .init(cloudcover: 0.0, time: 0.0, temperature: 0.0, windspeed: 0.0, wind_direction_10m: 0.0, weathercode: 0.0))
        
        let response = try await openMeteo.getForecast(.init(
            query: .init(
                latitude: coordinates.latitude,
                longitude: coordinates.longitude,
                hourly: [.temperature_2m, .apparent_temperature, .precipitation, .weathercode, .cloudcover, .windspeed_10m, .winddirection_10m, .precipitation_probability, .is_day],
                daily: [.precipitation_probability_max, .precipitation_sum, .sunrise, .sunset, .temperature_2m_max, .temperature_2m_min, .weathercode],
                current: [.cloudcover, .temperature, .wind_direction_10m, .weathercode, .windspeed, .precipitation, .is_day],
                timeformat: .unixtime,
                timezone: "auto",
                forecast_days: forecastDays
            )
        ))
                        
        switch response {
        case let .ok(response):
            switch response.body {
            case .json(let result):
                return result
            }
        case .badRequest(_):
            return fallbackForecast
        case .undocumented(statusCode: _, _):
            return fallbackForecast
        }
    }
    
    func getAirQuality(coordinates: CLLocationCoordinate2D) async throws -> Operations.getAirQuality.Output.Ok.Body.jsonPayload {
        let fallbackForecast: Operations.getAirQuality.Output.Ok.Body.jsonPayload = .init(latitude: 0, longitude: 0)
        
        let response = try await openMeteoAqi.getAirQuality(.init(
            query: .init(
                latitude: coordinates.latitude,
                longitude: coordinates.longitude,
                timezone: "auto", timeformat: .unixtime, forecast_days: ._1,
                hourly: [.european_aqi, .european_aqi_no2, .european_aqi_o3, .european_aqi_pm10, .european_aqi_pm10, .european_aqi_pm2_5, .european_aqi_so2, .uv_index]
            )
        ))
        
        switch response {
        case let .ok(response):
            switch response.body {
            case .json(let result):
                return result
            }
        case .undocumented(statusCode: _, _):
            return fallbackForecast
        }
    }
    
    func getAlerts(coordinates: CLLocationCoordinate2D) async throws -> [Components.Schemas.Alert] {
        let response = try await oscar.getAlerts(.init(
            query: .init(
                lat: coordinates.latitude,
                lon: coordinates.longitude
            )
        ))
        
        switch response {
        case let .ok(response):
            switch response.body {
            case .json(let result):
                return result
            }
        case .undocumented:
            return []
        }
    }
    
    func getRainForecast(coordinates: CLLocationCoordinate2D) async throws -> Components.Schemas.RainData {
        let response = try await oscar.getRain(.init(
            query: .init(
                lat: coordinates.latitude,
                lon: coordinates.longitude
            )
        ))
        
        switch response {
        case let .ok(response):
            switch response.body {
            case .json(let result):
                return result
            }
        case .undocumented:
            return .init()
        }
    }
    
    func getGeocodeSearchResult(name: String) async throws -> Components.Schemas.SearchResponse {
        let response = try await openMeteoGeo.search(.init(
            query: .init(name: name, language: "de")
        ))
        switch response {
        case let .ok(response):
            switch response.body {
            case .json(let result):
                return result
            }
        case .undocumented:
            return .init()
        }
    }
    
    func getRainRadar(coordinates: CLLocationCoordinate2D) async throws -> Components.Schemas.RadarResponse {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        let iso8601String = formatter.string(from: Date())
        let response = try await brightsky.getRainRadar(.init(
            query: .init(date: iso8601String, lat: coordinates.latitude, lon: coordinates.longitude, distance: 0, tz: "Europe/Berlin", format: .plain)
        ))
        switch response {
        case let .ok(response):
            switch response.body {
            case .json(let result):
                return result
            }
        case .undocumented:
            return .init()
        }
    }
}
