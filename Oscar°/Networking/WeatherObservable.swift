//
//  WeatherObservable.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.01.24.
//

import Foundation

@Observable
class Weather {
    var isLoading: Bool = false
    var forecast: Operations.getForecast.Output.Ok.Body.jsonPayload
    var alerts: Operations.getAlerts.Output.Ok.Body.jsonPayload
    var air: Operations.getAirQuality.Output.Ok.Body.jsonPayload
    var time: Double
    var radar: Components.Schemas.RadarResponse
    var error: String = ""
    var debug = false
    
    init() {
        time = 0
        forecast = Operations.getForecast.Output.Ok.Body.jsonPayload.init(
            latitude: 0.0,
            longitude: 0.0,
            current: .init(cloudcover: 0.0, time: 0.0, temperature: 0.0, windspeed: 0.0, wind_direction_10m: 0.0, weathercode: 0.0)
        )
        alerts = .init()
        air = Operations.getAirQuality.Output.Ok.Body.jsonPayload.init(latitude: 0, longitude: 0, hourly: nil)
        radar = .init()
    }
    
    // Update internal clock used for day simulation background
    func updateTime() {
        let dayBegin = self.forecast.hourly?.time.first ?? 0
        self.time = (Date.now.timeIntervalSince1970-dayBegin)/86400.0
    }
    
    private func currentTimeScaled() -> Double {
        let now = Date()
        let calendar = Calendar.current
        
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let second = calendar.component(.second, from: now)
        
        let totalSeconds = hour * 3600 + minute * 60 + second
        let secondsInADay = 24 * 3600
        
        return Double(totalSeconds) / Double(secondsInADay)
    }
}

extension Weather {
    static var mock: Weather {
        let mockWeather = Weather()
        
        // Generate 36 hours of mock hourly data
        let hourlyTimeInterval: TimeInterval = 3600 // 1 hour
        let hourlyStartTime = 1719266400.0
        let hourlyTimes = (0..<36).map { hourlyStartTime + Double($0) * hourlyTimeInterval }
        
        // Mock forecast data
        mockWeather.forecast = Operations.getForecast.Output.Ok.Body.jsonPayload(
            latitude: 51.34,
            longitude: 12.379999,
            elevation: 109.0,
            generationtime_ms: 1.9611120223999023,
            utc_offset_seconds: 7200,
            timezone_abbreviation: "CEST",
            hourly: Operations.getForecast.Output.Ok.Body.jsonPayload.hourlyPayload(
                time: hourlyTimes,
                temperature_2m: (0..<36).map { 18.0 + Double($0 % 24) / 2 }, // Temperature variation
                relativehumidity_2m: (0..<36).map { 70.0 + Double($0 % 12) }, // Humidity variation
                apparent_temperature: (0..<36).map { 17.0 + Double($0 % 24) / 2 }, // Apparent temperature variation
                pressure_msl: (0..<36).map { _ in 1019.0 + Double.random(in: -1...1) }, // Slight pressure variation
                cloudcover: (0..<36).map { _ in Double.random(in: 0...100) }, // Random cloud cover
                windspeed_10m: (0..<36).map { _ in Double.random(in: 5...15) }, // Random wind speed
                winddirection_10m: (0..<36).map { _ in Double.random(in: 0...360) }, // Random wind direction
                precipitation: (0..<36).map { _ in Double.random(in: 0...0.5) }, // Random light precipitation
                weathercode: (0..<36).map { _ in Double(Int.random(in: 0...3)) }, // Random weather codes
                is_day: (0..<36).map { $0 % 24 < 16 ? 1.0 : 0.0 } // Day time between 6am and 10pm
            ),
            daily: Components.Schemas.DailyResponse(
                time: (0..<5).map { hourlyStartTime + Double($0 * 86400) },
                temperature_2m_max: [28.0, 29.5, 27.8, 26.3, 30.1],
                temperature_2m_min: [14.8, 16.2, 15.5, 13.9, 17.3],
                precipitation_sum: [0.0, 2.5, 0.8, 0.0, 5.2],
                precipitation_probability_max: [0, 30, 20, 10, 60],
                weathercode: [2.0, 3.0, 1.0, 0.0, 3.0],
                sunrise: (0..<5).map { hourlyStartTime + 21600 + Double($0 * 86400) }, // Sunrise at 6 AM each day
                sunset: (0..<5).map { hourlyStartTime + 64800 + Double($0 * 86400) }  // Sunset at 6 PM each day
            ),
            current: Components.Schemas.CurrentWeather(
                cloudcover: 45.0,
                time: hourlyStartTime,
                temperature: 22.5,
                windspeed: 10.0,
                wind_direction_10m: 180.0,
                weathercode: 1.0,
                precipitation: 0.0,
                is_day: 1.0
            )
        )
        
        // Set other properties
        mockWeather.time = 0.5 // Midday
        mockWeather.alerts = .init() // Empty alerts
        mockWeather.air = Operations.getAirQuality.Output.Ok.Body.jsonPayload(latitude: 51.34, longitude: 12.379999, hourly: nil)
        mockWeather.radar = .init() // Empty radar
        
        return mockWeather
    }
}
