//
//  OMDayTemperature.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 10.04.23.
//

import Foundation

// MARK: - OMDayTemperature
struct OMDayTemperature: Codable {
    let latitude, longitude, generationtimeMS: Double
    let utcOffsetSeconds: Int
    let timezone, timezoneAbbreviation: String
    let elevation: Int
    let currentWeather: WidgetCurrentWeather
    let hourlyUnits: WidgetHourlyUnits
    let hourly: WidgetHourly
    let dailyUnits: WidgetDailyUnits
    let daily: WidgetDaily

    enum CodingKeys: String, CodingKey {
        case latitude, longitude
        case generationtimeMS = "generationtime_ms"
        case utcOffsetSeconds = "utc_offset_seconds"
        case timezone
        case timezoneAbbreviation = "timezone_abbreviation"
        case elevation
        case currentWeather = "current_weather"
        case hourlyUnits = "hourly_units"
        case hourly
        case dailyUnits = "daily_units"
        case daily
    }
}

// MARK: - CurrentWeather
struct WidgetCurrentWeather: Codable {
    let temperature: Double
    let windspeed: Double
    let winddirection, weathercode, isDay: Int
    let time: String

    enum CodingKeys: String, CodingKey {
        case temperature, windspeed, winddirection, weathercode
        case isDay = "is_day"
        case time
    }
    
    public func getWeatherIcon() -> String {
        if (isDay > 0) {
            switch weathercode {
            case 0, 1:
                return "sun.max.fill"
            case 2:
                return "cloud.sun.fill"
            case 3:
                return "cloud.fill"
            case 45, 48:
                return "cloud.fog.fill"
            case 51, 53, 55, 61, 63, 65:
                return "cloud.drizzle.fill"
            case 56, 57:
                return "cloud.sleet.fill"
            case 71, 73, 75, 77:
                return "cloud.snow.fill"
            case 80, 81, 82, 85, 86:
                return "cloud.heavyrain.fill"
            case 95, 96, 99:
                return "cloud.bolt.rain.fill"
            default:
                return "cloud.fill"
            }
        } else {
            switch weathercode {
            case 0, 1:
                return "moon.stars.fill"
            case 2:
                return "cloud.moon.fill"
            case 3:
                return "cloud.fill"
            case 45, 48:
                return "cloud.fog.fill"
            case 51, 53, 55, 61, 63, 65:
                return "cloud.drizzle.fill"
            case 56, 57:
                return "cloud.sleet.fill"
            case 71, 73, 75, 77:
                return "cloud.snow.fill"
            case 80, 81, 82, 85, 86:
                return "cloud.heavyrain.fill"
            case 95, 96, 99:
                return "cloud.bolt.rain.fill"
            default:
                return "cloud.fill"
            }
        }
    }
}

// MARK: - Daily
struct WidgetDaily: Codable {
    let time: [String]
    let temperature2MMax, temperature2MMin: [Double]

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2MMax = "temperature_2m_max"
        case temperature2MMin = "temperature_2m_min"
    }
}

// MARK: - DailyUnits
struct WidgetDailyUnits: Codable {
    let time, temperature2MMax, temperature2MMin: String

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2MMax = "temperature_2m_max"
        case temperature2MMin = "temperature_2m_min"
    }
}

// MARK: - Hourly
struct WidgetHourly: Codable {
    let time: [String]
    let precipitationProbability: [Int]
    let precipitation, windspeed10M, uvIndex: [Double]

    enum CodingKeys: String, CodingKey {
        case time
        case precipitationProbability = "precipitation_probability"
        case precipitation
        case windspeed10M = "windspeed_10m"
        case uvIndex = "uv_index"
    }
}

// MARK: - HourlyUnits
struct WidgetHourlyUnits: Codable {
    let time, precipitationProbability, precipitation, windspeed10M: String
    let uvIndex: String

    enum CodingKeys: String, CodingKey {
        case time
        case precipitationProbability = "precipitation_probability"
        case precipitation
        case windspeed10M = "windspeed_10m"
        case uvIndex = "uv_index"
    }
}
