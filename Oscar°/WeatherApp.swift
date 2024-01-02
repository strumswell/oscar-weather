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
    
    init() {
        forecast = Operations.getForecast.Output.Ok.Body.jsonPayload.init(
            latitude: 0.0,
            longitude: 0.0,
            current: .init(cloudcover: 0.0, time: "", temperature: 0.0, windspeed: 0.0, wind_direction_10m: 0.0, weathercode: 0.0)
        )
        
        alerts = []
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
    
    init () {
        openMeteo = Client(
            serverURL: try! Servers.server1(),
            transport: URLSessionTransport()
        )
        oscar = Client(
            serverURL: try! Servers.server2(),
            transport: URLSessionTransport()
        )
    }
    
    func getForecast(coordinates: CLLocationCoordinate2D) async throws -> Operations.getForecast.Output.Ok.Body.jsonPayload {
        let fallbackForecast: Operations.getForecast.Output.Ok.Body.jsonPayload = .init(latitude: coordinates.latitude, longitude: coordinates.longitude, current: .init(cloudcover: 0.0, time: "", temperature: 0.0, windspeed: 0.0, wind_direction_10m: 0.0, weathercode: 0.0))
        
        let response = try await openMeteo.getForecast(.init(
            query: .init(
                latitude: coordinates.latitude,
                longitude: coordinates.longitude,
                hourly: [.temperature_2m, .apparent_temperature, .precipitation, .weathercode, .cloudcover, .windspeed_10m, .winddirection_10m, .precipitation_probability],
                current: [.cloudcover, .temperature, .wind_direction_10m, .weathercode, .windspeed],
                timezone: "auto"
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

                        async let alerts = client.getAlerts(coordinates: location.coordinates)
                        weather.forecast = try await forecast
                        weather.alerts = try await alerts
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

