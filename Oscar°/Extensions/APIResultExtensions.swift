//
//  APIResultExtensions.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.01.24.
//

import Foundation

extension Components.Schemas.CurrentWeather {
    public func getWindDirection() -> String {
        let directions = [String(localized: "N_compass", comment: "North"), String(localized: "NE_compass", comment: "North-East"),
                          String(localized: "E_compass", comment: "East"), String(localized: "SE_compass", comment: "South-East"),
                          String(localized: "S_compass", comment: "South"), String(localized: "SW_compass", comment: "South-West"),
                          String(localized: "W_compass", comment: "West"), String(localized: "NW_compass", comment: "North-West")]
        let index = Int((self.wind_direction_10m + 22.5) / 45.0)
        return directions[min(max(index, 0), 8) % 8]
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
    
    func isExpectingRain() -> Bool {
        guard let radarData = radar else {
            return false
        }
        
        for timeframe in radarData {
            if let precipitationArray = timeframe.precipitation_5 {
                for row in precipitationArray {
                    for precipitation in row {
                        if precipitation > 0 {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }
}

extension PrecipSeriesResponse {
    /// The point nearest to "now", preferring observed frames over nowcast.
    private func nearestToNow() -> PrecipPoint? {
        let now = Date()
        let observed = series.filter { !$0.isForecast }
        let candidates = observed.isEmpty ? series : observed
        return candidates.min {
            abs($0.timestamp.timeIntervalSince(now)) < abs($1.timestamp.timeIntervalSince(now))
        }
    }

    /// Current precipitation rate in mm/h at "now" (nearest observed frame).
    var currentPrecipitation: Double {
        nearestToNow()?.precipitation ?? 0
    }

    /// Whether it is raining right now at the location.
    func isRaining() -> Bool {
        currentPrecipitation > 0
    }

    /// Whether any frame in the series (observed or nowcast) shows precipitation.
    func isExpectingRain() -> Bool {
        series.contains { $0.precipitation > 0 }
    }
}

extension Array {
    var middle: Element? {
        guard count != 0 else { return nil }
        
        let middleIndex = (count > 1 ? count - 1 : count) / 2
        return self[middleIndex]
    }
}
