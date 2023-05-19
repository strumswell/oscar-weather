//
//  RainModel.swift
//  Oscar°
//
//  Created by Philipp Bolte on 21.02.22.
//

import Foundation

struct RainRadarForecast: Codable {
    var data: [RainRadarDatapoint]
    
    public func getStartTime() -> String {
        let iso = ISO8601DateFormatter()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: iso.date(from: data.first?.time ?? "2022-01-01") ?? Date())
    }
    
    public func getMidTime() -> String {
        let iso = ISO8601DateFormatter()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: iso.date(from: data.middle?.time ?? "2022-01-01") ?? Date())
    }
    
    public func getFormattedTime(time: String) -> String {
        let iso = ISO8601DateFormatter()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: iso.date(from: time) ?? Date())
    }
    
    
    public func getEndTime() -> String {
        let iso = ISO8601DateFormatter()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: iso.date(from: data.last?.time ?? "2022-01-01") ?? Date())
    }
    
    func getMaxPreci() -> Double {
        var maxPreci = 0.0
        for datapoint in data {
            if (datapoint.mmh > maxPreci) {
                maxPreci = datapoint.mmh
            }
        }
        
        if (maxPreci <= 1 && maxPreci > 0) {
            return 1
        }
        return maxPreci
    }
    
    
}

struct RainRadarDatapoint: Codable, Hashable {
    let time: String
    let mmh: Double
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(time)
    }
}


// MARK: - Rain Forecats
struct RainForecast: Codable {
    let hasRain: Bool
    var data: [RainData]
    
    init() {
        self.hasRain = false
        self.data = []
        for index in 0...23 {
            data.insert(RainData(), at: index)
        }
    }
    
    public func getStartTime() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let rainData = getTimeAdjustedData()
        let startTime = Date(timeIntervalSince1970: Double(rainData.first?.timestamp ?? "0") ?? 0.0)
        return formatter.string(from: startTime)
    }
    
    public func getMidTime() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let rainData = getTimeAdjustedData()
        let startTime = Date(timeIntervalSince1970: Double(rainData.middle?.timestamp ?? "0") ?? 0.0)
        return formatter.string(from: startTime)
    }
    
    
    public func getEndTime() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let rainData = getTimeAdjustedData()
        let startTime = Date(timeIntervalSince1970: Double(rainData.last?.timestamp ?? "0") ?? 0.0)
        return formatter.string(from: startTime)
    }
    
    func getMaxPreci() -> Double {
        var maxPreci = 0.0
        for datapoint in getTimeAdjustedData() {
            if (datapoint.mm > maxPreci) {
                maxPreci = datapoint.mm
            }
        }
        
        if (maxPreci <= 2) {
            return 2
        }
        return maxPreci
    }
    
    func getTimeAdjustedData() -> [RainData] {
        let timestamp = NSDate().timeIntervalSince1970
        return data.filter {(Double($0.timestamp) ?? 0) >= timestamp }
    }
    
    func hasRainTimeAdjusted() -> Bool {
        let rain = getTimeAdjustedData().map( {$0.mm })
        return rain.reduce(0, +) > 0
    }
}

// MARK: - Datum
struct RainData: Codable {
    let time, timestamp, dbz: String
    let mm: Double
    init () {
        self.time = ""
        self.timestamp = ""
        self.dbz = ""
        self.mm = 0.0
    }
}

extension Array {
    var middle: Element? {
        guard count != 0 else { return nil }

        let middleIndex = (count > 1 ? count - 1 : count) / 2
        return self[middleIndex]
    }

}
