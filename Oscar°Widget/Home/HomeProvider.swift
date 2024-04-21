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
import Alamofire

struct HomeEntry: TimelineEntry {
    let date: Date
    let location: String
    let temperatureMin: Double
    let temperatureMax: Double
    let temperatureNow: Double
    let icon: String
    let backgroundGradients: [Color]
}

class HomeProvider: TimelineProvider {
    let client = APIClient()
    let locationService = LocationService.shared
    
    init() {

        locationService.update()
    }
    
    func placeholder(in context: Context) -> HomeEntry {
        HomeEntry(date: Date(), location: "Berlin", temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", backgroundGradients: [.sunriseStart, .sunnyDayEnd])
    }
    
    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> ()) {
        let entry = HomeEntry(date: Date(), location: "Berlin", temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", backgroundGradients: [.sunriseStart, .sunnyDayEnd])
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> ()) {
        locationService.update()

        Task {
            let coordinates = locationService.getCoordinates()
            let locationName = await locationService.getLocationName()

            // TODO: Do a different API call to get JUST the data we need here. The call gets too much.
            async let weatherRequest = client.getForecast(coordinates: coordinates, forecastDays: ._1)
            async let radarRequest = client.getRainForecast(coordinates: coordinates)
            let (weather, radar) = try await (weatherRequest, radarRequest)
            
            let dayBegin = weather.hourly?.time.first ?? 0
            let currentTime = (Date.now.timeIntervalSince1970-Double(dayBegin))/86400.0
            
            let temperatureMin = weather.daily?.temperature_2m_min?.first ?? 0
            let temperatureMax = weather.daily?.temperature_2m_max?.first ?? 0
            let temperatureNow = weather.current?.temperature ?? 0
            let weathercode = weather.current?.weathercode ?? 0
            let isDay = weather.current?.is_day ?? 0
            let precipitation = weather.current?.precipitation ?? 0
            let sunrise = weather.daily?.sunrise?.first ?? 0
            let sunset = weather.daily?.sunset?.first ?? 0          
            
            let entry = HomeEntry(
                date: Date(),
                location: locationName,
                temperatureMin: temperatureMin,
                temperatureMax: temperatureMax,
                temperatureNow: temperatureNow,
                icon: getWeatherIcon(weathercode: weathercode, isDay: isDay, isRaining: radar.isRaining(), precipitation: precipitation),
                backgroundGradients: [
                    self.getBackgroundTopStops(
                        dayBegin: dayBegin,
                        sunrise: sunrise,
                        sunset: sunset,
                        weathercode: weathercode,
                        isRaining: radar.isRaining(),
                        precipitation: precipitation)
                    .interpolated(amount: currentTime),
                    self.getBackgroundBottomStops(
                        dayBegin: dayBegin,
                        sunrise: sunrise,
                        sunset: sunset,
                        weathercode: weathercode,
                        isRaining: radar.isRaining(),
                        precipitation: precipitation)
                    .interpolated(amount: currentTime)
                ]
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

    
    func getBackgroundTopStops(dayBegin: Double, sunrise: Double, sunset: Double, weathercode: Double, isRaining: Bool, precipitation: Double) -> [Gradient.Stop] {
        let dayLength = 86400.0
        let isRaining = ((weathercode >= 51 && weathercode <= 99) && precipitation > 0) || isRaining

        if isRaining {
            return [
                .init(color: .midnightStart, location: 0),
                .init(color: .midnightStart, location: (sunrise - dayBegin)/dayLength - 0.08),
                .init(color: .rainyStart, location: (sunrise - dayBegin)/dayLength),
                .init(color: .rainyStart, location: (sunrise - dayBegin)/dayLength + 0.05),
                .init(color: .rainyStart, location: (sunset - dayBegin)/dayLength - 0.08),
                .init(color: .rainyStart, location: (sunset - dayBegin)/dayLength),
                .init(color: .midnightStart, location: (sunset - dayBegin)/dayLength + 0.04),
                .init(color: .midnightStart, location: 1)
            ]
        }
        
        return [
            .init(color: .midnightStart, location: 0),
            .init(color: .midnightStart, location: (sunrise - dayBegin)/dayLength - 0.08),
            .init(color: .sunriseStart, location: (sunrise - dayBegin)/dayLength),
            .init(color: .sunnyDayStart, location: (sunrise - dayBegin)/dayLength + 0.05),
            .init(color: .sunnyDayStart, location: (sunset - dayBegin)/dayLength - 0.08),
            .init(color: .sunsetStart, location: (sunset - dayBegin)/dayLength),
            .init(color: .midnightStart, location: (sunset - dayBegin)/dayLength + 0.04),
            .init(color: .midnightStart, location: 1)
        ]
        
    }
    
    func getBackgroundBottomStops(dayBegin: Double, sunrise: Double, sunset: Double, weathercode: Double, isRaining: Bool, precipitation: Double) -> [Gradient.Stop] {
        let dayLength = 86400.0
        let isRaining = ((weathercode >= 51 && weathercode <= 99) && precipitation > 0) || isRaining

        if isRaining {
            return [
                .init(color: .midnightEnd, location: 0),
                .init(color: .midnightEnd, location: (sunrise - dayBegin)/dayLength - 0.08),
                .init(color: .rainyEnd, location: (sunrise - dayBegin)/dayLength),
                .init(color: .rainyEnd, location: (sunrise - dayBegin)/dayLength + 0.05),
                .init(color: .rainyEnd, location: (sunset - dayBegin)/dayLength - 0.08),
                .init(color: .rainyEnd, location: (sunset - dayBegin)/dayLength),
                .init(color: .midnightEnd, location: (sunset - dayBegin)/dayLength + 0.015),
                .init(color: .midnightEnd, location: 1)
            ]
        }
        
        return [
            .init(color: .midnightEnd, location: 0),
            .init(color: .midnightEnd, location: (sunrise - dayBegin)/dayLength - 0.08),
            .init(color: .sunriseEnd, location: (sunrise - dayBegin)/dayLength),
            .init(color: .sunnyDayEnd, location: (sunrise - dayBegin)/dayLength + 0.05),
            .init(color: .sunnyDayEnd, location: (sunset - dayBegin)/dayLength - 0.08),
            .init(color: .sunsetEnd, location: (sunset - dayBegin)/dayLength),
            .init(color: .midnightEnd, location: (sunset - dayBegin)/dayLength + 0.015),
            .init(color: .midnightEnd, location: 1)
        ]
    }
}
