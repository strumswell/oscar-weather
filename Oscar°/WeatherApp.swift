//
//  WeatherApp.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.
//

import SwiftUI
import OpenAPIRuntime
import OpenAPIURLSession
import CoreLocation

@Observable
class Weather {
    var forecast: Operations.getForecast.Output.Ok.Body.jsonPayload
    var alerts: [Components.Schemas.Alert]
    var air: Operations.getAirQuality.Output.Ok.Body.jsonPayload
    var rain: Components.Schemas.RainData
    var time: Double
    
    init() {
        time = 0
        forecast = Operations.getForecast.Output.Ok.Body.jsonPayload.init(
            latitude: 0.0,
            longitude: 0.0,
            current: .init(cloudcover: 0.0, time: 0.0, temperature: 0.0, windspeed: 0.0, wind_direction_10m: 0.0, weathercode: 0.0)
        )
        alerts = []
        air = Operations.getAirQuality.Output.Ok.Body.jsonPayload.init(latitude: 0, longitude: 0)
        rain = .init()
    }
    
    // Update internal clock used for day simulation background
    func updateTime() {
        let dayBegin = self.forecast.hourly?.time.first ?? 0
        self.time = (Date.now.timeIntervalSince1970-dayBegin)/86400.0
    }
}

@Observable
class Location {
    var coordinates: CLLocationCoordinate2D
    var name: String
    
    init() {
        coordinates = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
        name = ""
    }
}

class APIClient {
    var openMeteo: Client
    var oscar: Client
    var openMeteoAqi: Client

    init () {
        openMeteo = Client(
            serverURL: try! Servers.server1(),
            transport: URLSessionTransport()
        )
        oscar = Client(
            serverURL: try! Servers.server2(),
            transport: URLSessionTransport()
        )
        openMeteoAqi = Client(
            serverURL: try! Servers.server3(),
            transport: URLSessionTransport()
        )
    }
    
    func getForecast(coordinates: CLLocationCoordinate2D) async throws -> Operations.getForecast.Output.Ok.Body.jsonPayload {
        let fallbackForecast: Operations.getForecast.Output.Ok.Body.jsonPayload = .init(latitude: coordinates.latitude, longitude: coordinates.longitude, current: .init(cloudcover: 0.0, time: 0.0, temperature: 0.0, windspeed: 0.0, wind_direction_10m: 0.0, weathercode: 0.0))
        
        let response = try await openMeteo.getForecast(.init(
            query: .init(
                latitude: coordinates.latitude,
                longitude: coordinates.longitude,
                hourly: [.temperature_2m, .apparent_temperature, .precipitation, .weathercode, .cloudcover, .windspeed_10m, .winddirection_10m, .precipitation_probability, .is_day],
                daily: [.precipitation_probability_max, .precipitation_sum, .sunrise, .sunset, .temperature_2m_max, .temperature_2m_min, .weathercode],
                current: [.cloudcover, .temperature, .wind_direction_10m, .weathercode, .windspeed, .precipitation],
                timeformat: .unixtime,
                timezone: "auto",
                forecast_days: ._14
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
    }

@main
struct WeatherApp: App {
    @State private var weather = Weather()
    @State private var location = Location()
    
    private let locationService = LocationService()
    private let client = APIClient()
    
    let persistenceController = PersistenceController.shared
    
    var body: some Scene {
        WindowGroup {
            NowView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(weather)
                .environment(location)
                .preferredColorScheme(.dark)
                .task {
                    do {
                        locationService.update()
                        location = await locationService.getLocation()
                        
                        async let forecast = client.getForecast(coordinates: location.coordinates)
                        async let airQuality = client.getAirQuality(coordinates: location.coordinates)
                        async let alerts = client.getAlerts(coordinates: location.coordinates)
                        async let rain = client.getRainForecast(coordinates: location.coordinates)
                        weather.forecast = try await forecast
                        weather.air = try await airQuality
                        weather.alerts = try await alerts
                        weather.rain = try await rain
                        weather.updateTime()
                    } catch {
                        print(error)
                    }
                }
        }
    }
}


extension Components.Schemas.CurrentWeather {
    public func getWindDirection() -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW", "N"]
        let index = Int((self.wind_direction_10m + 22.5) / 45.0)
        return directions[min(max(index, 0), 8)]
    }
}

extension View {
    public func getCurrentHour() -> Int {
        let currentDate = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: currentDate)
        return hour
    }
}

