//
//  OnboardingSampleData.swift
//  Oscar°
//

import Foundation

/// Deterministic fake data behind the feature-tour collage: real components,
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

    static let sunset = HourlySunEventItem(
        kind: .sunset,
        timestamp: 10,
        time: "21:32",
        weekday: String(localized: "Heute")
    )

    static let sunrise = HourlySunEventItem(
        kind: .sunrise,
        timestamp: 11,
        time: "05:04",
        weekday: String(localized: "Morgen")
    )

    static let gauges: [EnvironmentMetric] = [
        EnvironmentMetric.forAQI(id: "aqi", label: "AQI", value: 18),
        EnvironmentMetric.forUV(value: 6),
        EnvironmentMetric.forPollen(type: .grass, label: String(localized: "Gräser"), value: 22),
    ].compactMap { $0 }

    /// A warming-stripes series with the familiar cool-then-hot arc, pinned so
    /// the collage never changes. Jitter is a fixed hash of the year.
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
        DailyRow(id: 0, weekday: String(localized: "Heute"), iconName: "01d", low: 14, high: 27),
        DailyRow(id: 1, weekday: "Di", iconName: "02d", low: 15, high: 28),
        DailyRow(id: 2, weekday: "Mi", iconName: "10d", low: 13, high: 22),
        DailyRow(id: 3, weekday: "Do", iconName: "09d", low: 12, high: 19),
        DailyRow(id: 4, weekday: "Fr", iconName: "01d", low: 13, high: 24),
    ]

    static let dailyTemperatureBounds = (min: 10.0, max: 30.0)

    struct EnsembleSample {
        let low: Double
        let high: Double
        let spread: Double
    }

    static let ensembleSamples: [EnsembleSample] = {
        let lows: [Double] = [14, 15, 13, 12, 13, 15, 16]
        let highs: [Double] = [27, 28, 22, 19, 24, 26, 29]
        return (0..<7).map { day in
            EnsembleSample(low: lows[day], high: highs[day], spread: 0.6 + Double(day) * 0.55)
        }
    }()

    static let appIconPreviews: [String] = [
        "AppIconOriginalPreview",
        "AppIconChillDayPreview",
        "AppIconTVSunnyOscarPreview",
    ]

    static let appIconPreviewsAlternate: [String] = [
        "AppIconSpaceShipOscarPreview",
        "AppIconFlatOscarKawaiiPreview",
        "AppIconMechaOscarPreview",
    ]
}
