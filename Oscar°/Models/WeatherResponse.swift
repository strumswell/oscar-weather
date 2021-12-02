//
//  WeatherReponse.swift
//  Weather
//
//  Attribution:
//  Created by Ringo Wathelet on 2020/06/30. https://github.com/workingDog/OWOneCall/blob/master/Sources/OWOneCall/OWResponse.swift
//  Edited by Philipp Bolte on 06.10.20.
//

import Foundation

public struct WeatherResponse: Codable {
    public let lat, lon: Double
    public let timezone: String
    public let timezoneOffset: Int
    public let current: Current?
    public let minutely: [Minutely]?
    public let hourly: [Hourly]?
    public let daily: [Daily]?
    public let alerts: [Alert]?
    
    enum CodingKeys: String, CodingKey {
        case lat, lon, timezone, current, minutely, hourly, daily, alerts
        case timezoneOffset = "timezone_offset"
    }
    
    public init() {
        self.lat = 0.0
        self.lon = 0.0
        self.timezone = ""
        self.timezoneOffset = 0
        self.current = Current()
        self.minutely = []
        self.hourly = []
        self.daily = []
        self.alerts = []
    }
    
    public func weatherInfo() -> String {
        return current != nil ? current!.weatherInfo() : ""
    }
    
    public func getMaxPreciLabel() -> Double {
        var maxPreci = 0.0
        
        guard (minutely != nil) else {
            return 1.0
        }
        
        for minute in minutely! {
            if (minute.precipitation > maxPreci) {
                maxPreci = minute.precipitation
            }
        }
        if (maxPreci <= 1) {
            return 1.0
        }
        return maxPreci
    }
    
    public func getMaxPreci() -> Double {
        var maxPreci = 0.0
        
        guard (minutely != nil) else {
            return 0.0
        }
        
        for minute in minutely! {
            if (minute.precipitation > maxPreci) {
                maxPreci = minute.precipitation
            }
        }
        return maxPreci
    }
}

// MARK: - Alert
public struct Alert: Codable {
    let senderName, event: String
    let start, end: Int
    let alertDescription: String
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case senderName = "sender_name"
        case event, start, end
        case alertDescription = "description"
        case tags
    }
    
    func getFormattedEvent() -> String {
        switch(self.event) {
        case "persistent rain":
            return "DAUERREGEN"
        case "fog":
            return "NEBEL"
        case "Forest fire danger":
            return "WALDBRANDGEFAHR"
        default:
            return self.event
        }
    }
}

// MARK: - Current
public struct Current: Codable {
    
    public let dt, sunrise, sunset, pressure, humidity, clouds, visibility, windDeg: Int
    public let temp, feelsLike, dewPoint, uvi, windSpeed: Double
    public let windGust: Double?
    public let weather: [Weather]
    public let rain: Rain?
    public let snow: Snow?
 
    enum CodingKeys: String, CodingKey {
        case dt, sunrise, sunset, temp, pressure, humidity, uvi, clouds, visibility, weather, rain, snow
        case feelsLike = "feels_like"
        case dewPoint = "dew_point"
        case windSpeed = "wind_speed"
        case windDeg = "wind_deg"
        case windGust = "wind_gust"
    }
    
    public init() {
        self.dt = 0
        self.sunrise = 0
        self.sunset = 0
        self.temp = 0.0
        self.feelsLike = 0.0
        self.pressure = 0
        self.humidity = 0
        self.dewPoint = 0.0
        self.uvi = 0.0
        self.clouds = 0
        self.visibility = 0
        self.windSpeed = 0.0
        self.windDeg = 0
        self.weather = []
        self.rain = Rain()
        self.snow = Snow()
        self.windGust = 0.0
    }
    
    // convenience function
    public func getDate() -> Date {
        return Date(timeIntervalSince1970: TimeInterval(self.dt))
    }
    
    // convenience function
    public func weatherInfo() -> String {
        return (self.weather.first != nil)
            ? "\(self.weather.first!.weatherDescription.capitalized)"
            : ""
    }
    
    public func getIconString() -> String {
        return self.weather.first != nil ? self.weather.first!.icon : ""
    }

    // convenience function
    public func weatherIconName() -> String {
        return self.weather.first != nil ? self.weather.first!.iconNameFromId : "smiley"
    }
}

public struct Rain: Codable {
    public let the1H: Double?
    public let the3H: Double?
    
    enum CodingKeys: String, CodingKey {
        case the1H = "1h"
        case the3H = "3h"
    }
    
    public init() {
        self.the1H = 0.0
        self.the3H = 0.0
    }

    // for the case where we have:  "rain": { }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let theRain = try? values.decode(Rain.self, forKey: .the1H) {
            self.the1H = theRain.the1H
        } else {
            self.the1H = nil
        }
        if let theRain = try? values.decode(Rain.self, forKey: .the3H) {
            self.the3H = theRain.the3H
        } else {
            self.the3H = nil
        }
    }
    
}

public struct Snow: Codable {
    public let the1H: Double?
    public let the3H: Double?
    
    enum CodingKeys: String, CodingKey {
        case the1H = "1h"
        case the3H = "3h"
    }

    public init() {
        self.the1H = 0.0
        self.the3H = 0.0
    }
    
    // for the case where we have:  "snow": { }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let theSnow = try? values.decode(Snow.self, forKey: .the1H) {
            self.the1H = theSnow.the1H
        } else {
            self.the1H = nil
        }
        if let theSnow = try? values.decode(Snow.self, forKey: .the3H) {
            self.the3H = theSnow.the3H
        } else {
            self.the3H = nil
        }
    }
}

// MARK: - Weather
public struct Weather: Codable {
    public let id: Int
    public let main, weatherDescription, icon: String
    
    enum CodingKeys: String, CodingKey {
        case id, main, icon
        case weatherDescription = "description"
    }
    
    public init() {
        self.id = 0
        self.main = ""
        self.weatherDescription = ""
        self.icon = ""
    }
    
    public var iconNameFromId: String {
        switch id {
        case 200...232:  // thunderstorm
            return "cloud.bolt.rain"
        case 300...301: // drizzle
            return "cloud.drizzle"
        case 500...531: // rain
            return "cloud.rain"
        case 600...622: // snow
            return "cloud.snow"
        case 701...781: // fog, haze, dust
            return "cloud.fog"
        case 800:       //  clear sky
            return "sun.max"
        case 801...804:
            return "cloud.sun"
        default:
            return "cloud.sun"
        }
    }
}

// MARK: - Daily
public struct Daily: Codable, Hashable  {
    
    public let dt, sunrise, sunset, pressure, humidity, windDeg, clouds: Int
    public let dewPoint, windSpeed: Double
    public let windGust, rain, snow, uvi: Double?
    public let temp: DailyTemp
    public let feelsLike: FeelsLike
    public let weather: [Weather]
    public let pop: Double?
    public let visibility: Int?
    
    enum CodingKeys: String, CodingKey {
        case dt, sunrise, sunset, temp, pressure, humidity, visibility, weather, clouds, uvi, snow, rain, pop
        case feelsLike = "feels_like"
        case dewPoint = "dew_point"
        case windSpeed = "wind_speed"
        case windDeg = "wind_deg"
        case windGust = "wind_gust"
    }
    
    public init() {
        self.dt = 0
        self.sunrise = 0
        self.sunset = 0
        self.temp = DailyTemp()
        self.feelsLike = FeelsLike()
        self.pressure = 0
        self.humidity = 0
        self.dewPoint = 0.0
        self.uvi = 0.0
        self.clouds = 0
        self.windSpeed = 0.0
        self.windDeg = 0
        self.windGust = 0.0
        self.weather = []
        self.rain = 0.0
        self.snow = 0.0
        self.visibility = 0
        self.pop = 0.0
    }
    
    // convenience function
    public func getDate() -> Date {
        return Date(timeIntervalSince1970: TimeInterval(self.dt))
    }
    
    public func getWeekDay() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "de_DE")
        dateFormatter.dateFormat = "EEEE"
        return dateFormatter.string(from: self.getDate())
    }
    
    public func getIconString() -> String {
        return self.weather.first != nil ? self.weather.first!.icon : ""
    }
    
    public func getFormattedPop() -> String {
        return self.pop != nil ? String(format: "%.0f", (self.pop! * 100)) : ""
    }
    
    
    
    // convenience function
    public func weatherIconName() -> String {
        return self.weather.first != nil ? self.weather.first!.iconNameFromId : "smiley"
    }
    
    public static func == (lhs: Daily, rhs: Daily) -> Bool {
        lhs.dt == rhs.dt
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(dt)
    }
}

// MARK: - FeelsLike
public struct FeelsLike: Codable {
    
    public let day, night, eve, morn: Double
    
    public init() {
        self.day = 0.0
        self.night = 0.0
        self.eve = 0.0
        self.morn = 0.0
    }
}

// MARK: - DailyTemp
public struct DailyTemp: Codable {
    
    public let day, min, max, night, eve, morn: Double
    
    public init() {
        self.day = 0.0
        self.min = 0.0
        self.max = 0.0
        self.night = 0.0
        self.eve = 0.0
        self.morn = 0.0
    }
}

// MARK: - Hourly
public struct Hourly: Codable, Hashable {
    public let dt, pressure, humidity, clouds, windDeg: Int
    public let temp, feelsLike, dewPoint, windSpeed: Double
    public let windGust: Double?
    public let weather: [Weather]
    public let rain: Rain?
    public let snow: Snow?
    public let pop: Double?
    public let visibility: Int?
    
    enum CodingKeys: String, CodingKey {
        case dt, temp, pressure, humidity, visibility, clouds, weather, rain, snow, pop
        case feelsLike = "feels_like"
        case dewPoint = "dew_point"
        case windSpeed = "wind_speed"
        case windDeg = "wind_deg"
        case windGust = "wind_gust"
    }
    
    public init() {
        self.dt = 0
        self.temp = 0.0
        self.feelsLike = 0.0
        self.pressure = 0
        self.humidity = 0
        self.dewPoint = 0.0
        self.clouds = 0
        self.windSpeed = 0.0
        self.windDeg = 0
        self.windGust = 0.0
        self.weather = []
        self.rain = Rain()
        self.snow = Snow()
        self.pop = 0.0
        self.visibility = 0
    }
    
    // convenience function
    public func getDate() -> Date {
        return Date(timeIntervalSince1970: TimeInterval(self.dt))
    }
    
    public func getHourString() -> String {
        let preciDate = getDate()
        let calendar = Calendar.current
        let hours = calendar.component(.hour, from: preciDate)
        return String(format:"%02d", hours)
    }
    
    // convenience function
    public func weatherIconName() -> String {
        return self.weather.first != nil ? self.weather.first!.iconNameFromId : "smiley"
    }
    
    public func getDescription() -> String {
        return self.weather.first != nil ? self.weather.first!.main : ""
    }
    
    public func getIconString() -> String {
        return self.weather.first != nil ? self.weather.first!.icon : ""
    }
    
    public func getFormattedPop() -> String {
        return self.pop != nil ? String(format: "%.0f", (self.pop! * 100)) : ""
    }
    
    public static func == (lhs: Hourly, rhs: Hourly) -> Bool {
        lhs.dt == rhs.dt
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(dt)
    }
}

// MARK: - Minutely
public struct Minutely: Codable, Hashable {
    
    public let dt: Int
    public let precipitation: Double
    
    public init() {
        self.dt = 0
        self.precipitation = 0.0
    }
    
    // convenience function
    public func getDate() -> Date {
        return Date(timeIntervalSince1970: TimeInterval(self.dt))
    }
        
    public func getTimeString() -> String {
        let preciDate = getDate()
        let calendar = Calendar.current
        let hours = calendar.component(.hour, from: preciDate)
        let minutes = calendar.component(.minute, from: preciDate)
        return String(format:"%d:%02d", hours, minutes)
    }
    
    public func getHeight(maxHeight: Int, maxPreci: Double) -> Double {
        return (Double(maxHeight) / maxPreci) * self.precipitation
    }
}

