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
    let client = APIClient.shared

    func placeholder(in context: Context) -> TemperatureLockScreenEntry {
        TemperatureLockScreenEntry(date: Date(), temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", precipitation: 2.5, precipitationProbability: 72)
    }
    
    func getSnapshot(in context: Context, completion: @escaping @Sendable (TemperatureLockScreenEntry) -> ()) {
        let entry = TemperatureLockScreenEntry(date: Date(), temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", precipitation: 2.5, precipitationProbability: 72)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TemperatureLockScreenEntry>) -> ()) {
        Task {
            do {
                let coordinates = await MainActor.run {
                    LocationService.shared.update()
                    return LocationService.shared.getCoordinates()
                }

                async let weatherRequest = client.getForecast(
                    coordinates: coordinates,
                    forecastDays: ._1,
                    hourly: [.precipitation_probability]
                )
                async let radarRequest = client.getRadarSeries(coordinates: coordinates)
                let (weather, precipSeries) = try await (weatherRequest, radarRequest)

                let reportedMin = weather.daily?.temperature_2m_min?.first
                let reportedMax = weather.daily?.temperature_2m_max?.first
                let temperatureNow = weather.current?.temperature ?? 0
                let lowerTemperature = min(reportedMin ?? temperatureNow, reportedMax ?? temperatureNow)
                let upperTemperature = max(reportedMin ?? temperatureNow, reportedMax ?? temperatureNow)
                let temperatureMin = lowerTemperature < upperTemperature ? lowerTemperature : lowerTemperature - 0.5
                let temperatureMax = lowerTemperature < upperTemperature ? upperTemperature : upperTemperature + 0.5
                let weathercode = weather.current?.weathercode ?? 0
                let isDay = weather.current?.is_day ?? 0

                // Radar measures what is falling right now; the model's "current"
                // value is an interpolated guess (mirrors the Jetzt card's logic).
                let radarRate = precipSeries?.currentRate
                let precipitation = radarRate ?? (weather.current?.precipitation ?? 0.0)
                // Optional chaining only guards nil, not out-of-bounds: precipitation_probability
                // can be shorter than the time array, so index defensively.
                let probabilities = weather.hourly?.precipitation_probability ?? []
                let hourIndex = getLocalizedHourIndex(weather: weather)
                let precipitationProbability = probabilities.indices.contains(hourIndex) ? probabilities[hourIndex] : nil

                let isRaining = precipSeries?.isRaining() ?? false
                let icon = getWeatherIcon(weathercode: weathercode, isDay: isDay, isRaining: isRaining, precipitation: precipitation)

                let entry = TemperatureLockScreenEntry(date: Date(), temperatureMin: temperatureMin, temperatureMax: temperatureMax, temperatureNow: temperatureNow, icon: icon, precipitation: precipitation, precipitationProbability: Int(precipitationProbability ?? 0))

                let currentDate = Date()
                let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate)!
                let timeline = Timeline(entries:[entry], policy: .after(nextUpdateDate))
                completion(timeline)
            } catch {
                // completion must always be called: a dropped timeline request kills the
                // refresh chain and the widget never updates again. An empty timeline keeps
                // the last rendered entry on screen and retries once the API is back.
                let retryDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
                completion(Timeline(entries: [], policy: .after(retryDate)))
            }
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
