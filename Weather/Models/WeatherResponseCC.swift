//
//  WeatherResponseCC.swift
//  Weather
//
//  Created by Philipp Bolte on 28.10.20.
//

import Foundation

struct WeatherResponseCC: Codable {
    let lat: Double
    let lon: Double
    let temp, feelsLike, dewpoint, windSpeed, baroPressure, humidity, windDirection, precipitation, cloudCover: ValueUnit
    let precipitationType, sunrise, sunset, weatherCode, observationTime: Value

    enum CodingKeys: String, CodingKey {
        case lat, lon, temp
        case feelsLike = "feels_like"
        case dewpoint
        case windSpeed = "wind_speed"
        case baroPressure = "baro_pressure"
        case humidity
        case windDirection = "wind_direction"
        case precipitation
        case precipitationType = "precipitation_type"
        case cloudCover = "cloud_cover"
        case sunrise, sunset
        case weatherCode = "weather_code"
        case observationTime = "observation_time"
    }
    
    public init() {
        self.lat = 0.0
        self.lon = 0.0
        self.temp = ValueUnit()
        self.feelsLike = ValueUnit()
        self.dewpoint = ValueUnit()
        self.windSpeed = ValueUnit()
        self.baroPressure = ValueUnit()
        self.humidity = ValueUnit()
        self.windDirection = ValueUnit()
        self.precipitation = ValueUnit()
        self.cloudCover = ValueUnit()
        self.precipitationType = Value()
        self.sunrise = Value()
        self.sunset = Value()
        self.weatherCode = Value()
        self.observationTime = Value()
    }
}

// MARK: - ValueUnit
struct ValueUnit: Codable {
    let value: Double
    let units: String
    
    public init() {
        self.value = 0.0
        self.units = ""
    }
}

// MARK: - ObservationTime
struct Value: Codable {
    let value: String
    
    public init() {
        self.value = ""
    }
}
