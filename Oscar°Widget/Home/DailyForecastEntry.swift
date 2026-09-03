import Foundation
import SwiftUI
import WidgetKit

struct DayForecast: Identifiable {
    let id: Int
    let weekday: String
    let icon: String
    let precipProbability: Double?
    let precipSum: Double?
    let low: Double
    let high: Double
}

struct DailyForecastEntry: TimelineEntry {
    let date: Date
    let location: String
    let days: [DayForecast]
    let minTemp: Double
    let maxTemp: Double
    let temperatureUnit: String
    let precipitationUnit: String
    let backgroundGradient: LinearGradient

    static var placeholder: DailyForecastEntry {
        let samples: [(String, String, Double, Double, Double?)] = [
            ("Heute", "sun.max.fill", 12, 22, nil),
            ("Di", "cloud.sun.fill", 11, 18, 10),
            ("Mi", "cloud.rain.fill", 13, 24, 60),
            ("Do", "sun.max.fill", 14, 26, nil),
            ("Fr", "sun.max.fill", 14, 25, nil),
            ("Sa", "cloud.sun.fill", 12, 21, 20),
            ("So", "cloud.fill", 11, 19, 30),
        ]
        let days = samples.enumerated().map { index, sample in
            DayForecast(
                id: index,
                weekday: sample.0,
                icon: sample.1,
                precipProbability: sample.4,
                precipSum: nil,
                low: sample.2,
                high: sample.3
            )
        }
        return DailyForecastEntry(
            date: .now,
            location: "Berlin",
            days: days,
            minTemp: 11,
            maxTemp: 26,
            temperatureUnit: "°C",
            precipitationUnit: "mm",
            backgroundGradient: LinearGradient(
                colors: [.sunriseStart, .sunnyDayEnd], startPoint: .top, endPoint: .bottom)
        )
    }

    /// Rendered when the forecast fetch fails: keeps the resolved location visible (with no rows)
    /// so a configuration change always takes effect and a transient error never leaves the
    /// previously selected city's data on screen. WidgetKit retries per the timeline policy.
    static func unavailable(location: String) -> DailyForecastEntry {
        DailyForecastEntry(
            date: .now,
            location: location,
            days: [],
            minTemp: 0,
            maxTemp: 40,
            temperatureUnit: "°C",
            precipitationUnit: "mm",
            backgroundGradient: LinearGradient(
                colors: [.sunriseStart, .sunnyDayEnd], startPoint: .top, endPoint: .bottom)
        )
    }
}
