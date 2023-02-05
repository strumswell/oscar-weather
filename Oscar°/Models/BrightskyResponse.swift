//
//  BrightskyResponse.swift
//  Oscar°
//
//  Created by Philipp Bolte on 30.01.22.
//

import Foundation

// MARK: - Welcome
struct BrightskyResponse: Codable {
    let current: BDetail
    let hourly: [BDetail]
    let daily: [BDaily]
}

// MARK: - Current
struct BDetail: Codable, Hashable {
    let timestamp: Int
    let temp, wind: Double?
    let windDir: Int?
    let gust, prec, press: Double?
    let vis, clouds: Int?
    let icon: String
    
    // convenience function
    public func getDate() -> Date {
        return Date(timeIntervalSince1970: TimeInterval(self.timestamp / 1000))
    }
    
    public func getHourString() -> String {
        let date = getDate()
        let calendar = Calendar.current
        let hours = calendar.component(.hour, from: date)
        return String(format:"%02d", hours)
    }
    
    public func getRoundedTemp() -> String {
        return String(describing: (temp ?? 0.0).rounded()).replacingOccurrences(of: ".0", with: "") + "°"
    }
    
    public static func == (lhs: BDetail, rhs: BDetail) -> Bool {
        lhs.timestamp == rhs.timestamp
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(timestamp)
    }
}

// MARK: - Daily
struct BDaily: Codable, Hashable {
    let timestamp: Int
    let maxTemp, minTemp, prec: Double?
    let icon: String
    
    public func getDate() -> Date {
        return Date(timeIntervalSince1970: TimeInterval(self.timestamp / 1000))
    }
    
    public func getWeekDay() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "de_DE")
        dateFormatter.dateFormat = "EEEE"
        return dateFormatter.string(from: self.getDate())
    }
    
    public func getRoundedMinTemp() -> String {
        return String(describing: (minTemp ?? 0.0).rounded()).replacingOccurrences(of: ".0", with: "") + "°"
    }
    
    public func getRoundedMaxTemp() -> String {
        return String(describing: (maxTemp ?? 0.0).rounded()).replacingOccurrences(of: ".0", with: "") + "°"
    }
    
    public static func == (lhs: BDaily, rhs: BDaily) -> Bool {
        lhs.timestamp == rhs.timestamp
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(timestamp)
    }
}

