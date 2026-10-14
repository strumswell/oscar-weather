//
//  APIResultExtensions.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.01.24.
//

import Foundation

extension Components.Schemas.CurrentWeather {
    public func getWindDirection() -> String {
        compassDirection(wind_direction_10m)
    }
}

func compassDirection(_ degrees: Double) -> String {
    let directions = [String(localized: "N_compass", comment: "North"), String(localized: "NE_compass", comment: "North-East"),
                      String(localized: "E_compass", comment: "East"), String(localized: "SE_compass", comment: "South-East"),
                      String(localized: "S_compass", comment: "South"), String(localized: "SW_compass", comment: "South-West"),
                      String(localized: "W_compass", comment: "West"), String(localized: "NW_compass", comment: "North-West")]
    let index = Int((degrees + 22.5) / 45.0)
    return directions[min(max(index, 0), 8) % 8]
}

extension Operations.getForecast.Output.Ok.Body.jsonPayload {
    var locationTimeZone: TimeZone {
        timezone.flatMap(TimeZone.init(identifier:))
            ?? TimeZone(secondsFromGMT: utc_offset_seconds ?? 0)
            ?? .current
    }
}

extension PrecipSeriesResponse {
    private static let freshnessWindow: TimeInterval = 20 * 60

    func rate(at date: Date) -> Double? {
        guard let nearest = series.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        }), abs(nearest.timestamp.timeIntervalSince(date)) <= Self.freshnessWindow else {
            return nil
        }
        return nearest.precipitation
    }

    var currentRate: Double? {
        rate(at: Date())
    }

    var currentPrecipitation: Double {
        currentRate ?? 0
    }

    func isRaining() -> Bool {
        currentPrecipitation > 0
    }
}
