//
//  HomeProvider.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 03.06.23.
//

import Foundation
import CoreLocation
import SwiftUI
import WidgetKit
import simd

struct HomeEntry: TimelineEntry {
    let date: Date
    let location: String
    let temperatureMin: Double
    let temperatureMax: Double
    let temperatureNow: Double
    let icon: String
    let backgroundGradient: LinearGradient
}

class HomeProvider: TimelineProvider {
    let client = APIClient.shared
    let locationService = LocationService.shared
    private let atmosphericAdapter = WeatherAtmosphericAdapter()
    
    init() {
        locationService.update()
    }
    
    func placeholder(in context: Context) -> HomeEntry {
        let placeholderGradient = LinearGradient(colors: [.sunriseStart, .sunnyDayEnd], startPoint: .top, endPoint: .bottom)
        return HomeEntry(date: Date(), location: "Berlin", temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", backgroundGradient: placeholderGradient)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> ()) {
        let placeholderGradient = LinearGradient(colors: [.sunriseStart, .sunnyDayEnd], startPoint: .top, endPoint: .bottom)
        let entry = HomeEntry(date: Date(), location: "Berlin", temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", backgroundGradient: placeholderGradient)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> ()) {
        locationService.update()

        Task {
            let coordinates = locationService.getCoordinates()
            let locationName = await locationService.getLocationName()

            async let weatherRequest = client.getForecast(
                coordinates: coordinates,
                forecastDays: ._1,
                hourly: [
                    .weathercode, .cloudcover, .relativehumidity_2m, .pressure_msl,
                    .precipitation, .snowfall, .windspeed_10m, .winddirection_10m,
                ]
            )
            async let radarRequest = client.getRainRadar(coordinates: coordinates)
            let (weather, radar) = try await (weatherRequest, radarRequest)
            
            let dayBegin = weather.hourly?.time.first ?? 0
            let currentTime = (Date.now.timeIntervalSince1970-Double(dayBegin))/86400.0
            
            let temperatureMin = weather.daily?.temperature_2m_min?.first ?? 0
            let temperatureMax = weather.daily?.temperature_2m_max?.first ?? 0
            let temperatureNow = weather.current?.temperature ?? 0
            let weathercode = weather.current?.weathercode ?? 0
            let isDay = weather.current?.is_day ?? 0
            let precipitation = weather.current?.precipitation ?? 0          
            
            // Create Weather object for atmospheric rendering
            let weatherForRendering = Weather()
            weatherForRendering.time = currentTime
            weatherForRendering.forecast = weather // Use the existing forecast data
            weatherForRendering.radar = radar
            weatherForRendering.debug = true // Enable debug for troubleshooting
            
            // Get atmospheric gradient for widget background (full 12-sample gradient)
            let backgroundGradient = atmosphericAdapter.getWidgetFullGradient(
                from: weatherForRendering,
                at: coordinates
            )

            // Debug output for troubleshooting
            if weatherForRendering.debug {
                print("🔧 Widget Debug - Location: \(coordinates)")
                print("🔧 Widget Debug - Time: \(currentTime)")
                print("🔧 Widget Debug - Weather code: \(weathercode)")
                print("🔧 Widget Debug - Temperature: \(temperatureNow)")
                print("🔧 Widget Debug - Using full atmospheric gradient")
            }

            let entry = HomeEntry(
                date: Date(),
                location: locationName,
                temperatureMin: temperatureMin,
                temperatureMax: temperatureMax,
                temperatureNow: temperatureNow,
                icon: getWeatherIcon(weathercode: weathercode, isDay: isDay, isRaining: radar.isRaining(), precipitation: precipitation),
                backgroundGradient: backgroundGradient
            )
            
            let currentDate = Date()
            let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate)!
            let timeline = Timeline(entries:[entry], policy: .after(nextUpdateDate))
            completion(timeline)
        }
    }
    
    public func getWeatherIcon(weathercode: Double, isDay: Double, isRaining: Bool, precipitation: Double) -> String {
        let shouldShowRainingIcon = isRaining || precipitation > 0

        if (isDay > 0) {
            switch weathercode {
            case 0, 1:
                return shouldShowRainingIcon ? "cloud.drizzle.fill" : "sun.max.fill"
            case 2:
                return shouldShowRainingIcon ? "cloud.drizzle.fill" : "cloud.sun.fill"
            case 3:
                return shouldShowRainingIcon ? "cloud.drizzle.fill" : "cloud.fill"
            case 45, 48:
                return shouldShowRainingIcon ? "cloud.drizzle.fill" : "cloud.fog.fill"
            case 51, 53, 55, 61, 63, 65:
                return shouldShowRainingIcon ? "cloud.drizzle.fill" : "cloud.fill"
            case 56, 57:
                return shouldShowRainingIcon ? "cloud.sleet.fill" : "cloud.fill"
            case 71, 73, 75, 77:
                return shouldShowRainingIcon ?"cloud.snow.fill" : "cloud.fill"
            case 80, 81, 82, 85, 86:
                return shouldShowRainingIcon ? "cloud.heavyrain.fill" : "cloud.fill"
            case 95, 96, 99:
                return shouldShowRainingIcon ? "cloud.bolt.rain.fill" : "cloud.fill"
            default:
                return "cloud.fill"
            }
        } else {
            switch weathercode {
            case 0, 1:
                return shouldShowRainingIcon ? "cloud.drizzle.fill" : "moon.stars.fill"
            case 2:
                return shouldShowRainingIcon ? "cloud.drizzle.fill" : "cloud.moon.fill"
            case 3:
                return shouldShowRainingIcon ? "cloud.drizzle.fill" : "cloud.fill"
            case 45, 48:
                return shouldShowRainingIcon ? "cloud.drizzle.fill" : "cloud.fog.fill"
            case 51, 53, 55, 61, 63, 65:
                return shouldShowRainingIcon ? "cloud.drizzle.fill" : "cloud.fill"
            case 56, 57:
                return shouldShowRainingIcon ? "cloud.sleet.fill" : "cloud.fill"
            case 71, 73, 75, 77:
                return shouldShowRainingIcon ? "cloud.snow.fill" : "cloud.fill"
            case 80, 81, 82, 85, 86:
                return shouldShowRainingIcon ? "cloud.heavyrain.fill" : "cloud.fill"
            case 95, 96, 99:
                return shouldShowRainingIcon ? "cloud.bolt.rain.fill" : "cloud.fill"
            default:
                return "cloud.fill"
            }
        }
    }
}
