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

final class HomeProvider: TimelineProvider, Sendable {
    let client = APIClient.shared

    func placeholder(in context: Context) -> HomeEntry {
        let placeholderGradient = LinearGradient(colors: [.sunriseStart, .sunnyDayEnd], startPoint: .top, endPoint: .bottom)
        return HomeEntry(date: Date(), location: "Berlin", temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", backgroundGradient: placeholderGradient)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (HomeEntry) -> ()) {
        let placeholderGradient = LinearGradient(colors: [.sunriseStart, .sunnyDayEnd], startPoint: .top, endPoint: .bottom)
        let entry = HomeEntry(date: Date(), location: "Berlin", temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", backgroundGradient: placeholderGradient)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<HomeEntry>) -> ()) {
        Task {
            do {
                let coordinates = await MainActor.run {
                    LocationService.shared.update()
                    return LocationService.shared.getCoordinates()
                }
                let locationName = await LocationService.shared.getLocationName()

                async let weatherRequest = client.getForecast(
                    coordinates: coordinates,
                    forecastDays: ._1,
                    hourly: [
                        .weathercode, .cloudcover, .relativehumidity_2m, .pressure_msl,
                        .precipitation, .snowfall, .windspeed_10m, .winddirection_10m,
                    ]
                )
                async let radarRequest = client.getRadarSeries(coordinates: coordinates)
                let (weather, precipSeries) = try await (weatherRequest, radarRequest)

                let dayBegin = weather.hourly?.time.first ?? 0
                let currentTime = (Date.now.timeIntervalSince1970-Double(dayBegin))/86400.0

                let temperatureMin = weather.daily?.temperature_2m_min?.first ?? 0
                let temperatureMax = weather.daily?.temperature_2m_max?.first ?? 0
                let temperatureNow = weather.current?.temperature ?? 0
                let weathercode = weather.current?.weathercode ?? 0
                let isDay = weather.current?.is_day ?? 0
                let precipitation = weather.current?.precipitation ?? 0

                // Build the atmospheric gradient on the main actor (Weather + adapter are
                // @MainActor); only the resulting Sendable gradient crosses back.
                let backgroundGradient = await MainActor.run {
                    let weatherForRendering = Weather()
                    weatherForRendering.time = currentTime
                    weatherForRendering.forecast = weather
                    weatherForRendering.precipSeries = precipSeries
                    return WeatherAtmosphericAdapter().getWidgetFullGradient(
                        from: weatherForRendering,
                        at: coordinates
                    )
                }

                let entry = HomeEntry(
                    date: Date(),
                    location: locationName,
                    temperatureMin: temperatureMin,
                    temperatureMax: temperatureMax,
                    temperatureNow: temperatureNow,
                    icon: getWeatherIcon(weathercode: weathercode, isDay: isDay, isRaining: precipSeries?.isRaining() ?? false, precipitation: precipitation),
                    backgroundGradient: backgroundGradient
                )

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
