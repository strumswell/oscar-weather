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

extension PrecipSeriesResponse {
    /// How far the sample nearest to "now" may be from the wall clock before the
    /// series counts as stale (e.g. the app slept in the background) and reads as
    /// "no data" instead of replaying an outdated value.
    private static let freshnessWindow: TimeInterval = 20 * 60

    /// The point nearest to "now" across the whole series — observed *or* nowcast.
    /// Radar observations lag the wall clock by 5–15 min, so shortly after rain
    /// starts the value that is actually "now" lives in the nowcast half;
    /// preferring observed frames here used to read a stale dry frame while the
    /// chart already showed rain.
    private func nearestToNow() -> PrecipPoint? {
        let now = Date()
        guard let nearest = series.min(by: {
            abs($0.timestamp.timeIntervalSince(now)) < abs($1.timestamp.timeIntervalSince(now))
        }), abs(nearest.timestamp.timeIntervalSince(now)) <= Self.freshnessWindow else {
            return nil
        }
        return nearest
    }

    /// Precipitation rate in mm/h at "now", or nil when the series has no sample
    /// near the current time (stale data). Lets callers with their own fallback
    /// (e.g. the forecast value) tell "radar says dry" apart from "no radar".
    var currentRate: Double? {
        nearestToNow()?.precipitation
    }

    /// Current precipitation rate in mm/h at "now" (nearest frame, 0 when stale).
    var currentPrecipitation: Double {
        currentRate ?? 0
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
