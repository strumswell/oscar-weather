//
//  OpenMeteoResponse.swift
//  Oscar°
//
//  Created by Philipp Bolte on 07.08.22.
//

import Foundation
import UIKit

// MARK: - OpenMeteoResponse
struct OpenMeteoResponse: Codable {
    let latitude, longitude, generationtimeMS: Double
    let utcOffsetSeconds, elevation: Int
    let currentWeather: CurrentWeather
    let hourlyUnits: HourlyUnits
    let hourly: Hourly
    let dailyUnits: DailyUnits
    let daily: Daily

    enum CodingKeys: String, CodingKey {
        case latitude, longitude
        case generationtimeMS = "generationtime_ms"
        case utcOffsetSeconds = "utc_offset_seconds"
        case elevation
        case currentWeather = "current_weather"
        case hourlyUnits = "hourly_units"
        case hourly
        case dailyUnits = "daily_units"
        case daily
    }
    
    public func getDate(timestamp: Double) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
    
    public func getWeatherIcon(weathercode: Double, timestamp: Double, sunrise: Double, sunset: Double) -> String {
        let now = getDate(timestamp: timestamp)
        let sunriseDate = getDate(timestamp: sunrise)
        let sunsetDate = getDate(timestamp: sunset)
        
        if (now > sunriseDate && now < sunsetDate) {
            switch weathercode {
            case 0, 1:
                return "01d"
            case 2:
                return "02d"
            case 3:
                return "04d"
            case 45, 48:
                return "50d"
            case 51:
                return "10d"
            case 71, 73, 75, 77:
                return "13d"
            case 95, 96, 99:
                return "11d"
            default:
                return "09d"
            }
        } else {
            switch weathercode {
            case 0, 1:
                return "01n"
            case 2:
                return "02n"
            case 3:
                return "04n"
            case 45, 48:
                return "50n"
            case 51:
                return "10n"
            case 71, 73, 75, 77:
                return "13n"
            case 95, 96, 99:
                return "11n"
            default:
                return "09n"
            }
        }
    }

    
    public func getCurrentHourPos() -> Int {
        let now = Date().timeIntervalSince1970
        var lastIndex = 0
        for (idx, time) in (hourly.time).enumerated() {
            if (now <= time ?? 0.0) {
                return lastIndex
            }
            lastIndex = idx
        }
        return lastIndex
    }
    
    public func getDayOfHour(timestamp: Double) -> Int {
        var pos = 0
        for (idx, time) in (daily.time).enumerated() {
            if (timestamp >= time ?? 0.0) {
                pos = idx
            }
        }
        return pos
    }
    
    public func getHourlySize() -> Int {
        return (hourly.time).count;
    }
    
    public func getHourString(pos: Int) -> String {
        let date = getDate(timestamp: hourly.time[pos] ?? 0.0)
        let calendar = Calendar.current
        let hours = calendar.component(.hour, from: date)
        return String(format:"%02d", hours)
    }
    
    
    public func getHourTemp(pos: Int) -> String {
        return String(describing: (hourly.temperature2M[pos] ?? 0.0).rounded()).replacingOccurrences(of: ".0", with: "") + "°"
    }
    
    public func getHourPrec(pos: Int) -> Double {
        return hourly.precipitation[pos] ?? 0.0
    }
    
    
    public func getHourIcon(pos: Int) -> String {
        let timestamp = hourly.time[pos] ?? 0.0
        let currentDay = getDayOfHour(timestamp: timestamp)
        return getWeatherIcon(weathercode: hourly.weathercode[pos] ?? 0.0, timestamp: timestamp, sunrise: daily.sunrise[currentDay], sunset: daily.sunset[currentDay])
    }
    
    public func getCurrentIcon() -> String {
        let timestamp = currentWeather.time
        return getWeatherIcon(weathercode: Double(currentWeather.weathercode), timestamp: Double(timestamp), sunrise: daily.sunrise[0], sunset: daily.sunset[0])
    }
    
    public func getCurrentCloudCover() -> Double {
        let currentHour = getCurrentHourPos()
        return hourly.cloudcover[currentHour] ?? 0.0
    }
}

// MARK: - CurrentWeather
struct CurrentWeather: Codable {
    let temperature, windspeed: Double
    let winddirection, weathercode, time: Int
    
    public func getDate(timestamp: Double) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
    
    public func getRoundedTempString() -> String {
        return String(describing: temperature.rounded()).replacingOccurrences(of: ".0", with: "") + "°"
    }
    
    public func getRoundedTemp() -> String {
        return String(describing: temperature.rounded()).replacingOccurrences(of: ".0", with: "")
    }
    
    public func getWindDirection() -> String {
        switch self.winddirection {
        case let x where x > 0 && x < 20:
            return "N"
        case let x where x >= 20 && x < 80:
            return "NE"
        case let x where x >= 80 && x < 100:
            return "E"
        case let x where x >= 100 && x < 170:
            return "SE"
        case let x where x >= 170 && x < 190:
            return "S"
        case let x where x >= 190 && x < 260:
            return "SW"
        case let x where x >= 260 && x < 330:
            return "W"
        case let x where x >= 330:
            return "NW"
        default:
            return "N/A"
        }
    }
    
    public func getWeatherIcon() -> String {
        switch self.weathercode {
        case 0, 1:
            return "01d"
        case 2:
            return "02d"
        case 3:
            return "04d"
        case 45, 48:
            return "50d"
        case 51:
            return "10d"
        case 71, 73, 75, 77:
            return "13d"
        case 95, 96, 99:
            return "11d"
        default:
            return "09d"
        }
    }
}

// MARK: - Daily
struct Daily: Codable {
    let time, weathercode, temperature2MMax, temperature2MMin: [Double?]
    let sunrise, sunset: [Double]
    let precipitationSum, precipitationHours: [Double?]
    let windspeed10MMax, winddirection10MDominant, shortwaveRadiationSum: [Double?]

    enum CodingKeys: String, CodingKey {
        case time, weathercode
        case temperature2MMax = "temperature_2m_max"
        case temperature2MMin = "temperature_2m_min"
        case sunrise, sunset
        case precipitationSum = "precipitation_sum"
        case precipitationHours = "precipitation_hours"
        case windspeed10MMax = "windspeed_10m_max"
        case winddirection10MDominant = "winddirection_10m_dominant"
        case shortwaveRadiationSum = "shortwave_radiation_sum"
    }

    public func getDate(timestamp: Double) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
    
    public func getWeekDay(pos: Int) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "de_DE")
        dateFormatter.dateFormat = "EEEE"
        return dateFormatter.string(from: getDate(timestamp: time[pos] ?? 0.0))
    }
    
    public func getRoundedMinTemp(pos: Int) -> String {
        return String(describing: (temperature2MMin[pos] ?? 0.0).rounded()).replacingOccurrences(of: ".0", with: "") + "°"
    }
    
    public func getRoundedMaxTemp(pos: Int) -> String {
        return String(describing: (temperature2MMax[pos] ?? 0.0).rounded()).replacingOccurrences(of: ".0", with: "") + "°"
    }
    
    public func getWeatherIcon(pos: Int) -> String {
        switch weathercode[pos] {
        case 0, 1:
            return "01d"
        case 2:
            return "02d"
        case 3:
            return "04d"
        case 45, 48:
            return "50d"
        case 51:
            return "10d"
        case 71, 73, 75, 77:
            return "13d"
        case 95, 96, 99:
            return "11d"
        default:
            return "09d"
        }
    }

}

// MARK: - DailyUnits
struct DailyUnits: Codable {
    let time, weathercode, temperature2MMax, temperature2MMin: String
    let sunrise, sunset, precipitationSum, precipitationHours: String
    let windspeed10MMax, winddirection10MDominant, shortwaveRadiationSum: String

    enum CodingKeys: String, CodingKey {
        case time, weathercode
        case temperature2MMax = "temperature_2m_max"
        case temperature2MMin = "temperature_2m_min"
        case sunrise, sunset
        case precipitationSum = "precipitation_sum"
        case precipitationHours = "precipitation_hours"
        case windspeed10MMax = "windspeed_10m_max"
        case winddirection10MDominant = "winddirection_10m_dominant"
        case shortwaveRadiationSum = "shortwave_radiation_sum"
    }
    
    public func getDate(timestamp: Double) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
    
    public func getRoundedTempString(temperature: Double) -> String {
        return String(describing: temperature.rounded()).replacingOccurrences(of: ".0", with: "") + "°"
    }
    
    public func getWeatherIcon(weathercode: Double) -> String {
        switch weathercode {
            case 0, 1:
                return "01d"
            case 2:
                return "02d"
            case 3:
                return "04d"
            case 45, 48:
                return "50d"
            case 51:
                return "10d"
            case 71, 73, 75, 77:
                return "13d"
            case 95, 96, 99:
                return "11d"
            default:
                return "09d"
            
        }
    }
}

// MARK: hourly
struct Hourly: Codable {
    let time, temperature2M, apparentTemperature, surfacePressure: [Double?]
    let precipitation, weathercode, cloudcover, windspeed10M: [Double?]
    let winddirection10M, soilTemperature6CM, soilMoisture3_9CM: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2M = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case surfacePressure = "surface_pressure"
        case precipitation, weathercode, cloudcover
        case windspeed10M = "windspeed_10m"
        case winddirection10M = "winddirection_10m"
        case soilTemperature6CM = "soil_temperature_6cm"
        case soilMoisture3_9CM = "soil_moisture_3_9cm"
    }

    public func getDate(timestamp: Double) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    public func getRoundedTempString(temperature: Double) -> String {
        return String(describing: temperature.rounded()).replacingOccurrences(of: ".0", with: "") + "°"
    }
    
    public func getWeatherIcon(weathercode: Double, timestamp: Double, sunrise: Double, sunset: Double) -> String {
        let now = getDate(timestamp: timestamp)
        let sunriseDate = getDate(timestamp: sunrise)
        let sunsetDate = getDate(timestamp: sunset)
        
        if (now > sunriseDate && now < sunsetDate) {
            switch weathercode {
            case 0, 1:
                return "01d"
            case 2:
                return "02d"
            case 3:
                return "04d"
            case 45, 48:
                return "50d"
            case 51:
                return "10d"
            case 71, 73, 75, 77:
                return "13d"
            case 95, 96, 99:
                return "11d"
            default:
                return "09d"
            }
        } else {
            switch weathercode {
            case 0, 1:
                return "01n"
            case 2:
                return "02n"
            case 3:
                return "04n"
            case 45, 48:
                return "50n"
            case 51:
                return "10n"
            case 71, 73, 75, 77:
                return "13n"
            case 95, 96, 99:
                return "11n"
            default:
                return "09n"
            }
        }
    }

    public func getHour() -> Int {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour], from: now)
        return components.hour! - 1
    }
}

// MARK: - HourlyUnits
struct HourlyUnits: Codable {
    let time, temperature2M, apparentTemperature, surfacePressure: String
    let precipitation, weathercode, cloudcover, windspeed10M: String
    let winddirection10M, soilTemperature6CM, soilMoisture3_9CM: String

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2M = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case surfacePressure = "surface_pressure"
        case precipitation, weathercode, cloudcover
        case windspeed10M = "windspeed_10m"
        case winddirection10M = "winddirection_10m"
        case soilTemperature6CM = "soil_temperature_6cm"
        case soilMoisture3_9CM = "soil_moisture_3_9cm"
    }
}
