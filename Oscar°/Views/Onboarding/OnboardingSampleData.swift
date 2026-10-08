//
//  OnboardingSampleData.swift
//  Oscar°
//

import Foundation

/// Deterministic fake data behind the feature pages: real components,
/// staged values that never change between launches.
@MainActor
enum OnboardingSampleData {
    static let hourlyItems: [HourlyForecastItem] = [
        HourlyForecastItem(
            timestamp: 0,
            hour: String(localized: "Jetzt"),
            precipitation: "0 mm",
            iconName: "01d",
            temperature: "23°",
            isNow: true
        ),
        HourlyForecastItem(
            timestamp: 1,
            hour: String(localized: "15 Uhr"),
            precipitation: "0 mm",
            iconName: "02d",
            temperature: "24°"
        ),
        HourlyForecastItem(
            timestamp: 2,
            hour: String(localized: "16 Uhr"),
            precipitation: "0,2 mm",
            iconName: "10d",
            temperature: "22°",
            precipitationValue: 0.2
        ),
        HourlyForecastItem(
            timestamp: 3,
            hour: String(localized: "17 Uhr"),
            precipitation: "0,8 mm",
            iconName: "09d",
            temperature: "20°",
            precipitationValue: 0.8
        ),
        HourlyForecastItem(
            timestamp: 4,
            hour: String(localized: "18 Uhr"),
            precipitation: "0 mm",
            iconName: "02d",
            temperature: "21°"
        ),
        HourlyForecastItem(
            timestamp: 5,
            hour: String(localized: "22 Uhr"),
            precipitation: "0 mm",
            iconName: "01n",
            temperature: "17°"
        ),
    ]

    static let gauges: [EnvironmentMetric] = [
        EnvironmentMetric.forAQI(id: "aqi", label: "AQI", value: 18),
        EnvironmentMetric.forUV(value: 6),
        EnvironmentMetric.forPollen(type: .grass, label: String(localized: "Gräser"), value: 22),
    ].compactMap { $0 }

    /// A warming-stripes series with the familiar cool-then-hot arc, pinned so
    /// the stage never changes. Jitter is a fixed hash of the year.
    static let climateStripes: [ClimateStripe] = (1940...2026).map { year in
        let progress = Double(year - 1940) / 86.0
        let trend = -0.55 + pow(progress, 2.1) * 2.3
        let jitter = (Double((year * 7919) % 97) / 97.0 - 0.5) * 0.7
        let anomaly = trend + jitter
        return ClimateStripe(year: year, value: 20 + anomaly, anomaly: anomaly)
    }

    struct DailyRow: Identifiable {
        let id: Int
        let weekday: String
        let iconName: String
        let low: Double
        let high: Double
    }

    static let dailyRows: [DailyRow] = [
        ("01d", 14.0, 27.0), ("02d", 15, 28), ("10d", 13, 22), ("09d", 12, 19), ("01d", 13, 24),
    ].enumerated().map { day, values in
        let date = Calendar.current.date(byAdding: .day, value: day, to: .now) ?? .now
        let weekday = day == 0 ? String(localized: "Heute") : date.formatted(.dateTime.weekday(.abbreviated))
        return DailyRow(id: day, weekday: weekday, iconName: values.0, low: values.1, high: values.2)
    }

    static let dailyTemperatureBounds = (min: 10.0, max: 30.0)

    /// Sixteen days of a 30-run ensemble: close together at first, fanning out
    /// over the second week, rain today. Same shape as the screenshot fixture.
    static let ensembleDays: [EnsembleDay] = {
        let highs: [Double] = [16, 19, 22, 24, 26, 25, 21, 24, 27, 25, 23, 22, 24, 26, 27, 25]
        let lows: [Double] = [13, 12, 13, 14, 15, 16, 14, 13, 15, 16, 14, 13, 14, 15, 16, 15]
        let rain: [Double] = [32, 9, 0.5, 0, 0, 0.3, 5, 0, 0, 1, 3, 6, 2, 0, 0, 4]
        let winds: [Double] = [30, 22, 14, 10, 9, 12, 18, 11, 9, 13, 15, 17, 12, 10, 11, 14]
        let runs = 1...30
        let today = Calendar.current.startOfDay(for: .now)

        return highs.indices.map { day in
            /// Each run wobbles around the day's value; wider the further out.
            func spread(_ base: Double, _ width: Double) -> [Double] {
                runs.map { run in base + sin(Double(run) * 1.7 + Double(day) * 0.9) * width }
            }
            let width = 0.7 + Double(day) * 0.38
            let precipitation = runs.map { run in
                let phase = Double(run) * 1.7
                return max(0, rain[day] * (1 + sin(phase) * 0.25) + sin(phase + Double(day) * 0.9) * (0.4 + Double(day) * 0.9))
            }
            let codes = zip(runs, precipitation).map { run, mm in
                mm >= 5 ? 63 : mm >= 1 ? 61 : mm >= 0.2 ? 51 : [0, 2, 3][(run + day) % 3]
            }
            return EnsembleDay(
                id: day,
                noon: today.addingTimeInterval(Double(day) * 86_400 + 12 * 3600).timeIntervalSince1970,
                runs: runs.count,
                high: EnsembleSpread(spread(highs[day], width)),
                low: EnsembleSpread(spread(lows[day], width * 0.8)),
                precipitation: EnsembleSpread(precipitation),
                wind: EnsembleSpread(spread(winds[day], 1.2 + Double(day) * 0.35).map { max(4, $0) }),
                snowfall: 0,
                cloudCover: nil,
                sky: EnsembleSkyMix(codes: codes)
            )
        }
    }()

    /// Now, on a ten-minute mark, so staged times read like real ones.
    private static let stagedNow: Date = {
        let tenMinutes = 10.0 * 60
        return Date(timeIntervalSinceReferenceDate: (Date.now.timeIntervalSinceReferenceDate / tenMinutes).rounded(.down) * tenMinutes)
    }()

    /// A shower passing through over the next two hours.
    static let showerPoints: [PrecipChartPoint] = (0...24).map { step in
        let progress = Double(step) / 24
        return PrecipChartPoint(
            date: stagedNow.addingTimeInterval(Double(step) * 300),
            value: 2.4 * exp(-pow((progress - 0.4) / 0.18, 2))
        )
    }

    /// Three stations around a mild day: cool night, warm afternoon.
    static let stations: [Components.Schemas.NearbyStation] = [
        ("Leipzig/Halle", 14.2, 302.0, 0.0),
        ("Leipzig-Holzhausen", 6.1, 118.0, -1.1),
        ("Oschatz", 47.9, 81.0, -2.0),
    ].map { name, distance, bearing, offset in
        let end = stagedNow
        let history = (0...24).map { hour in
            Components.Schemas.StationReading(
                time: end.addingTimeInterval(Double(hour - 24) * 3600),
                temperature_c: 13 + offset - 6 * cos(Double(hour + 3) / 24 * 2 * .pi))
        }
        return Components.Schemas.NearbyStation(
            id: name, name: name, source: "esoh", latitude: 51.34, longitude: 12.37,
            distance_km: distance, bearing_deg: bearing, last_report_at: end, current: history[24], history: history)
    }
}
