//
//  WeatherApp.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.
//

import SwiftUI

@main
struct WeatherApp: App {
    @State private var weather = Weather()
    @State private var location = Location()
    private let locationService = LocationService.shared
    private let client = APIClient()
    private let persistenceController = PersistenceController.shared
    
    var body: some Scene {
        WindowGroup {
            NowView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(weather)
                .environment(location)
                .preferredColorScheme(.dark)
                .task {
                    await updateState()
                }
        }
    }
}

extension WeatherApp {
    public func updateState() async {
        do {
            if weather.isLoading { return }
            weather.isLoading = true
            
            locationService.update()
            location = await locationService.getLocation()
                        
            async let forecastRequest = client.getForecast(coordinates: location.coordinates)
            async let airQualityRequest = client.getAirQuality(coordinates: location.coordinates)
            async let radarRequest = client.getRainRadar(coordinates: location.coordinates)
            let (forecastResponse, airQualityResponse, radarResponse) = try await (forecastRequest, airQualityRequest, radarRequest)
            weather.forecast = forecastResponse
            weather.air = airQualityResponse
            weather.radar = radarResponse
            weather.updateTime()
            weather.isLoading = false
            
            let alertsResponse = try await client.getAlerts(coordinates: location.coordinates)
            weather.alerts = alertsResponse
        } catch {
            print(error)
        }
    }
}
