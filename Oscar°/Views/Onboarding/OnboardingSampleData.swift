//
//  OnboardingSampleData.swift
//  Oscar°
//

import Foundation

@MainActor
enum OnboardingSampleData {
    static var hourlyItems: [HourlyForecastItem] {
        let units = SettingService.shared.units
        let samples: [(hour: String, icon: String, celsius: Double, mm: Double)] = [
            (String(localized: "Jetzt"), "01d", 23, 0),
            (String(localized: "15 Uhr"), "02d", 24, 0),
            (String(localized: "16 Uhr"), "10d", 22, 0.2),
            (String(localized: "17 Uhr"), "09d", 20, 0.8),
            (String(localized: "18 Uhr"), "02d", 21, 0),
            (String(localized: "22 Uhr"), "01n", 17, 0),
        ]
        return samples.enumerated().map { index, sample in
            HourlyForecastItem(
                timestamp: Double(index),
                hour: sample.hour,
                precipitation: units.precipitationString(sample.mm),
                iconName: sample.icon,
                temperature: units.temperatureString(sample.celsius),
                isNow: index == 0,
                precipitationValue: sample.mm
            )
        }
    }

    static let gauges: [EnvironmentMetric] = [
        EnvironmentMetric.forAQI(id: "aqi", label: "AQI", value: 18),
        EnvironmentMetric.forUV(value: 6),
        EnvironmentMetric.forPollen(type: .grass, label: String(localized: "Gräser"), value: 22),
        EnvironmentMetric.forAQI(id: "pm25", label: "PM", subscript_: "2.5", value: 14),
        EnvironmentMetric.forAQI(id: "pm10", label: "PM", subscript_: "10", value: 11),
        EnvironmentMetric.forPollen(type: .birch, label: String(localized: "Birke"), value: 4),
        EnvironmentMetric.forAQI(id: "no2", label: "NO", subscript_: "2", value: 9),
    ].compactMap { $0 }

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

    static let ensembleDays: [EnsembleDay] = {
        let highs: [Double] = [16, 19, 22, 24, 26, 25, 21, 24, 27, 25, 23, 22, 24, 26, 27, 25]
        let lows: [Double] = [13, 12, 13, 14, 15, 16, 14, 13, 15, 16, 14, 13, 14, 15, 16, 15]
        let rain: [Double] = [32, 9, 0.5, 0, 0, 0.3, 5, 0, 0, 1, 3, 6, 2, 0, 0, 4]
        let winds: [Double] = [30, 22, 14, 10, 9, 12, 18, 11, 9, 13, 15, 17, 12, 10, 11, 14]
        let runs = 1...30
        let today = Calendar.current.startOfDay(for: .now)

        return highs.indices.map { day in
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
                wetShare: EnsembleDay.wetShare(of: precipitation),
                wind: EnsembleSpread(spread(winds[day], 1.2 + Double(day) * 0.35).map { max(4, $0) }),
                snowfall: 0,
                cloudCover: nil,
                sky: EnsembleSkyMix(codes: codes)
            )
        }
    }()

    private static let stagedNow: Date = {
        let tenMinutes = 10.0 * 60
        return Date(timeIntervalSinceReferenceDate: (Date.now.timeIntervalSinceReferenceDate / tenMinutes).rounded(.down) * tenMinutes)
    }()

    static let showerPoints: [PrecipChartPoint] = (0...24).map { step in
        let progress = Double(step) / 24
        return PrecipChartPoint(
            date: stagedNow.addingTimeInterval(Double(step) * 300),
            value: 2.4 * exp(-pow((progress - 0.4) / 0.18, 2))
        )
    }

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
