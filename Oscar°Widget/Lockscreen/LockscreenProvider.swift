//
//  LockscreenProvider.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 10.04.23.
//

import Foundation
import CoreLocation
import SwiftUI
import WidgetKit
import Alamofire

struct TemperatureLockScreenEntry: TimelineEntry {
    let date: Date
    let temperatureMin: Double
    let temperatureMax: Double
    let temperatureNow: Double
    let icon: String
    let precipitation: Double
    let precipitationProbability: Int
}

struct LockscreenProvider: TimelineProvider {
    let client = APIClient()
    let locationService = LocationService.shared
    
    init() {
        locationService.update()
    }

    func placeholder(in context: Context) -> TemperatureLockScreenEntry {
        TemperatureLockScreenEntry(date: Date(), temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", precipitation: 2.5, precipitationProbability: 72)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (TemperatureLockScreenEntry) -> ()) {
        let entry = TemperatureLockScreenEntry(date: Date(), temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", precipitation: 2.5, precipitationProbability: 72)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<TemperatureLockScreenEntry>) -> ()) {
        locationService.update()

        Task {
            let coordinates = locationService.getCoordinates()
            
            // TODO: Do a different API call to get JUST the data we need here. The call gets too much.
            async let weatherRequest = client.getForecast(coordinates: coordinates, forecastDays: ._1)
            async let radarRequest = client.getRainForecast(coordinates: coordinates)
            let (weather, radar) = try await (weatherRequest, radarRequest)
                        
            let temperatureMin = weather.daily?.temperature_2m_min?.first ?? 0
            let temperatureMax = weather.daily?.temperature_2m_max?.first ?? 0
            let temperatureNow = weather.current?.temperature ?? 0
            let weathercode = weather.current?.weathercode ?? 0
            let isDay = weather.current?.is_day ?? 0
            
            // TODO: Respect radar data for precipitation + probability
            let precipitation = weather.current?.precipitation ?? 0.0
            let precipitationProbability = weather.hourly?.precipitation_probability?[getLocalizedHourIndex(weather: weather)]
            
            let isRaining = radar.isRaining()
            let icon = getWeatherIcon(weathercode: weathercode, isDay: isDay, isRaining: isRaining, precipitation: precipitation)
            
            let entry = TemperatureLockScreenEntry(date: Date(), temperatureMin: temperatureMin, temperatureMax: temperatureMax, temperatureNow: temperatureNow, icon: icon, precipitation: precipitation, precipitationProbability: Int(precipitationProbability ?? 0))
            
            let currentDate = Date()
            let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate)!
            let timeline = Timeline(entries:[entry], policy: .after(nextUpdateDate))
            completion(timeline)
        }
    }
    
    public func getLocalizedHourIndex(weather: Operations.getForecast.Output.Ok.Body.jsonPayload) -> Int {
        let currentUnixTime = weather.current?.time ?? 0
        let hours = weather.hourly?.time ?? []
        
        // Initialize variables to track the closest time and its index
        var closestTime = Double.greatestFiniteMagnitude
        var closestIndex = -1
        
        for (index, time) in hours.enumerated() {
            // Check the absolute difference between current time and each time in the array
            let difference = abs(currentUnixTime - time)
            if difference < closestTime {
                closestTime = difference
                closestIndex = index
            }
        }
        
        // Check if a closest time was found
        if closestIndex != -1 {
            return closestIndex
        } else {
            return 0
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
