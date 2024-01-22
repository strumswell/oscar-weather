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
    var alerts: [Components.Schemas.Alert]
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
        alerts = []
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
