//
//  APIResultExtensions.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.01.24.
//

import Foundation

extension Components.Schemas.CurrentWeather {
    public func getWindDirection() -> String {
        let directions = [String(localized: "N_compass"), String(localized: "NE_compass"), String(localized: "E_compass"),
                          String(localized: "SE_compass"), String(localized: "S_compass"), String(localized: "SW_compass"),
                          String(localized: "W_compass"), String(localized: "NW_compass"), String(localized: "N_compass")]
        let index = Int((self.wind_direction_10m + 22.5) / 45.0)
        return directions[min(max(index, 0), 8)]
    }
}

extension Components.Schemas.RainData {
    func isRaining() -> Bool {
        if (data?.isEmpty) == nil {
            return false
        }
        
        if data?.first?.mmh ?? 0 > 0 {
            return true
        }
        
        return false
    }
}

extension Components.Schemas.RadarResponse {
    func isRaining() -> Bool {
        if (radar?.first) == nil {
            return false
        }
        
        if radar?.first?.precipitation_5?.first?.first ?? 0 > 0 {
            return true
        }
        
        return false
    }
}

extension Components.Schemas.Alert {
    func getFormattedHeadline() -> String {
        guard let headline = headline else {
            return ""
        }

        return headline
            .replacingOccurrences(of: "Amtliche", with: "")
            .replacingOccurrences(of: "UNWETTER", with: "")
    }
    
    public func getStartDate() -> String {
        return formatDate(time: self.start ?? 0.0)
    }
    
    public func getEndDate() -> String {
        return formatDate(time: self.end ?? 0.0)
    }
    
    public func formatDate(time: Double) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(Int(time) / 1000))
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "de")
        return dateFormatter.string(from: date)
    }
}
