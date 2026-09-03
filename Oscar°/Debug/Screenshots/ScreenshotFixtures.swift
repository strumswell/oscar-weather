#if DEBUG
//
//  ScreenshotFixtures.swift
//  Oscar°
//
//  Wire-format payloads served by ScreenshotFixtureServer: a heavy-rain "now"
//  that clears into a warm week, with matching air quality, a severe-rain
//  alert, a dramatic radar series, a warming climate archive, and a widening
//  ensemble. Everything anchors to `storyNow` (tomorrow, 14:00 local) so
//  "now"-relative views line up in daylight; the values themselves never
//  change between runs.
//

import Foundation
import ImageIO
import UIKit

enum ScreenshotFixtures {
    static let latitude = 51.3397
    static let longitude = 12.3731

    /// Every fixture timestamp hangs off this instant instead of the launch
    /// clock: tomorrow at 14:00 local. Two reasons. The set renders in daylight
    /// whatever time of day the pipeline runs — the sky, the hourly icons and
    /// every clock label agree on early afternoon. And because the served
    /// arrays never straddle the real "now", `AtmosphereWeatherMapper` falls
    /// through to `current.time` for the sky instead of the device clock (it
    /// prefers the device clock only while the forecast actually covers it).
    /// Tomorrow, not today, so the story is always ahead of the real clock;
    /// 14:00 rather than noon so no clock label in the set has to render a
    /// 12-hour "12:30 PM", which is wide enough to collide with its neighbour
    /// on the rain chart's axis.
    static var storyNow: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        return calendar.date(bySettingHour: 14, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    static var storyDayStart: Date { Calendar.current.startOfDay(for: storyNow) }

    /// Two scenes tell a different story than the rain set: a sunny summer day
    /// with no precipitation and no alert.
    private static var sunnyStory: Bool {
        ScreenshotMode.scene == .nowForecast || ScreenshotMode.scene == .nowClear
    }

    /// Fixture copy ships per-language here instead of the localization
    /// catalog — it is marketing staging, not product UI. The alert banner and
    /// detail sheet read the `_de` fields regardless of locale, so the switch
    /// happens at fixture-build time.
    private static func localized(de: String, en: String, tr: String) -> String {
        switch Locale.current.language.languageCode?.identifier {
        case "de": de
        case "tr": tr
        default: en
        }
    }

    // MARK: - Forecast (api.open-meteo.com)

    static func forecastJSON() -> [String: Any] {
        let calendar = Calendar.current
        let now = storyNow
        let dayStart = storyDayStart
        let hourIndex = calendar.component(.hour, from: now)

        let hourCount = 48
        let times = (0..<hourCount).map { dayStart.timeIntervalSince1970 + Double($0) * 3600 }

        // Story, in hours relative to launch: heavy rain now, easing over the
        // afternoon, showers by evening, clearing into a warm sunny stretch.
        // The forecast scene (sunnyStory) swaps this for a calm summer day.
        func precipitation(_ dt: Int) -> Double {
            if sunnyStory { return 0 }
            return switch dt {
            case ..<0: 4.2
            case 0: 8.6
            case 1: 7.4
            case 2: 5.2
            case 3: 3.1
            case 4: 1.8
            case 5: 0.9
            case 6: 0.4
            case 7: 0.2
            default: 0
            }
        }
        func weathercode(_ dt: Int) -> Double {
            if sunnyStory {
                // Mostly sunny with a few fair-weather clouds drifting through
                // the hourly strip: sun stays the dominant impression.
                let hour = (dt + hourIndex + 48) % 24
                guard (8...19).contains(hour) else { return 1 }
                return hour % 4 == 1 ? 2 : (hour % 2 == 0 ? 1 : 0)
            }
            return switch dt {
            case ..<2: 65
            case 2...3: 63
            case 4...5: 61
            case 6...7: 80
            case 8...10: 3
            case 11...14: 2
            default: 1
            }
        }
        func temperature(_ dt: Int) -> Double {
            if sunnyStory {
                let hour = Double((dt + hourIndex + 48) % 24)
                return 18 + 9 * exp(-pow((hour - 15) / 4.5, 2))
            }
            let clearing = min(max(Double(dt) - 6, 0), 16)
            return 14.0 + clearing * 0.5
        }

        let dts = (0..<hourCount).map { $0 - hourIndex }
        let hourly: [String: Any] = [
            "time": times,
            "temperature_2m": dts.map(temperature),
            "relativehumidity_2m": dts.map { sunnyStory ? 52 : 94 - min(max(Double($0) - 4, 0), 20) * 1.8 },
            "apparent_temperature": dts.map { temperature($0) - (sunnyStory ? 0.6 : 1.4) },
            "pressure_msl": dts.map { sunnyStory ? 1022 : 1004 + min(max(Double($0), -6), 30) * 0.4 },
            "cloudcover": dts.map { sunnyStory ? 22 : min(100, max(15, 100 - max(Double($0) - 5, 0) * 7)) },
            "windspeed_10m": dts.map { sunnyStory ? 11 : max(12, 32 - max(Double($0), 0) * 1.1) },
            "winddirection_10m": dts.map { 245 + Double(($0 % 8) * 3) },
            "precipitation": dts.map(precipitation),
            "precipitation_probability": dts.map { dt -> Double in
                if sunnyStory { return 3 }
                return switch dt {
                case ..<4: 100
                case 4...7: 70
                case 8...12: 25
                default: 8
                }
            },
            "weathercode": dts.map(weathercode),
            "snowfall": Array(repeating: 0.0, count: hourCount),
            "soil_temperature_0cm": dts.map { 15 + min(max(Double($0) - 6, 0), 20) * 0.2 },
            "soil_temperature_6cm": Array(repeating: 15.5, count: hourCount),
            "soil_temperature_18cm": Array(repeating: 15.0, count: hourCount),
            "soil_temperature_54cm": Array(repeating: 14.2, count: hourCount),
            "soil_moisture_0_1cm": dts.map { min(0.42, 0.34 + max(0, 4 - abs(Double($0))) * 0.02) },
            "soil_moisture_1_3cm": Array(repeating: 0.33, count: hourCount),
            "soil_moisture_3_9cm": Array(repeating: 0.31, count: hourCount),
            "soil_moisture_9_27cm": Array(repeating: 0.29, count: hourCount),
            "soil_moisture_27_81cm": Array(repeating: 0.27, count: hourCount),
            "et0_fao_evapotranspiration": (0..<hourCount).map { i -> Double in
                let hour = Double(i % 24)
                return max(0, 0.32 * exp(-pow((hour - 14) / 4, 2)))
            },
            "is_day": (0..<hourCount).map { (5...20).contains($0 % 24) ? 1.0 : 0.0 },
        ]

        let dayCount = 12
        let dailyTimes = (0..<dayCount).map { dayStart.timeIntervalSince1970 + Double($0) * 86_400 }
        let daily: [String: Any] = [
            "time": dailyTimes,
            // Rain story: today is a warm day broken by heavy afternoon storms
            // (high 24°, but 14° right now under the downpour). Keeps the
            // climate section on the warming message — today reads warm vs the
            // ~23° July normal rather than "coldest ever" off a cold daily high.
            "temperature_2m_max": sunnyStory
                ? [27, 28, 26, 27, 29, 28, 26, 25, 27, 28, 26, 27]
                : [24, 19, 22, 24, 26, 25, 21, 24, 27, 25, 23, 26],
            "temperature_2m_min": sunnyStory
                ? [16, 17, 16, 15, 17, 18, 16, 15, 16, 17, 16, 16]
                : [13, 12, 13, 14, 15, 16, 14, 13, 15, 16, 14, 15],
            "precipitation_sum": sunnyStory
                ? Array(repeating: 0.0, count: dayCount)
                : [38.4, 11.2, 0.4, 0, 0, 0.2, 6.8, 0, 0, 0.6, 0, 0.2],
            "precipitation_probability_max": sunnyStory
                ? [0, 0, 5, 0, 0, 5, 10, 0, 0, 5, 0, 0]
                : [100, 85, 30, 5, 0, 15, 65, 5, 0, 25, 10, 20],
            "weathercode": sunnyStory
                ? [0, 0, 1, 0, 0, 1, 2, 1, 0, 0, 1, 0]
                : [65, 80, 3, 1, 0, 2, 61, 1, 0, 3, 1, 2],
            "sunrise": dailyTimes.map { $0 + 5 * 3600 },
            "sunset": dailyTimes.map { $0 + 21.5 * 3600 },
        ]

        return [
            "latitude": latitude,
            "longitude": longitude,
            "elevation": 38,
            "generationtime_ms": 0.5,
            "utc_offset_seconds": TimeZone.current.secondsFromGMT(),
            "timezone_abbreviation": TimeZone.current.abbreviation() ?? "CEST",
            "hourly": hourly,
            "hourly_units": [
                "time": "unixtime",
                "temperature_2m": "°C",
                "apparent_temperature": "°C",
                "precipitation": "mm",
                "weathercode": "wmo code",
                "cloudcover": "%",
                "windspeed_10m": "km/h",
                "winddirection_10m": "°",
                "soil_temperature_0cm": "°C",
                "soil_moisture_0_1cm": "m³/m³",
                "et0_fao_evapotranspiration": "mm",
            ],
            "daily": daily,
            "daily_units": [
                "time": "unixtime",
                "temperature_2m_max": "°C",
                "temperature_2m_min": "°C",
                "precipitation_sum": "mm",
                "precipitation_probability_max": "%",
                "weathercode": "wmo code",
            ],
            "current": [
                "cloudcover": sunnyStory ? 20 : 100,
                "time": dayStart.timeIntervalSince1970 + Double(hourIndex) * 3600,
                "temperature": sunnyStory ? (temperature(0) * 10).rounded() / 10 : 14.3,
                "windspeed": sunnyStory ? 11 : 32,
                "wind_direction_10m": 245,
                "weathercode": sunnyStory ? weathercode(0) : 65,
                "precipitation": sunnyStory ? 0 : 8.6,
                "is_day": 1,
            ],
        ]
    }

    // MARK: - Air quality (air-quality-api.open-meteo.com)

    static func airQualityJSON() -> [String: Any] {
        let dayStart = storyDayStart
        let hourCount = 72
        let times = (0..<hourCount).map { dayStart.timeIntervalSince1970 + Double($0) * 3600 }

        // Diurnal curves: ozone and UV peak in the afternoon, particulates and
        // NO₂ around the commutes. Day one stays subdued under the rain.
        func bell(_ hourOfDay: Double, peak: Double, width: Double) -> Double {
            let x = (hourOfDay - 14) / width
            return peak * exp(-x * x)
        }
        let uvPeaks: [Double] = [2.5, 5.5, 6.5]
        var aqi: [Double] = []
        var pm25: [Double] = []
        var pm10: [Double] = []
        var no2: [Double] = []
        var o3: [Double] = []
        var so2: [Double] = []
        var uv: [Double] = []
        var grass: [Double] = []
        var mugwort: [Double] = []
        var ragweed: [Double] = []
        for i in 0..<hourCount {
            let day = i / 24
            let hour = Double(i % 24)
            let commute = exp(-pow((hour - 8) / 2.5, 2)) + exp(-pow((hour - 18) / 2.5, 2))
            aqi.append((21 + 5 * sin(hour / 24 * 2 * .pi) + Double(day) * 2).rounded())
            pm25.append((11 + 4 * commute + Double(day)).rounded())
            pm10.append((17 + 5 * commute + Double(day)).rounded())
            no2.append((13 + 7 * commute).rounded())
            o3.append((26 + bell(hour, peak: 16, width: 4) + Double(day) * 3).rounded())
            so2.append((5 + commute).rounded())
            uv.append((bell(hour, peak: uvPeaks[day], width: 3) * 10).rounded() / 10)
            let pollenDamp = day == 0 ? 0.4 : 1.0
            grass.append((bell(hour, peak: 26, width: 5) * pollenDamp).rounded())
            mugwort.append((bell(hour, peak: 8, width: 5) * pollenDamp).rounded())
            ragweed.append((bell(hour, peak: 3, width: 5) * pollenDamp).rounded())
        }

        return [
            "latitude": latitude,
            "longitude": longitude,
            "hourly": [
                "time": times,
                "european_aqi": aqi,
                "european_aqi_pm2_5": pm25,
                "european_aqi_pm10": pm10,
                "european_aqi_no2": no2,
                "european_aqi_o3": o3,
                "european_aqi_so2": so2,
                "uv_index": uv,
                "alder_pollen": Array(repeating: 0.0, count: hourCount),
                "birch_pollen": Array(repeating: 0.0, count: hourCount),
                "grass_pollen": grass,
                "mugwort_pollen": mugwort,
                "olive_pollen": Array(repeating: 0.0, count: hourCount),
                "ragweed_pollen": ragweed,
            ] as [String: Any],
        ]
    }

    // MARK: - Alerts (oscar-server /weather-alerts/point)

    static func alertsJSON() -> [String: Any] {
        if sunnyStory { return ["alertCount": 0, "alerts": [] as [Any]] }
        let formatter = ISO8601DateFormatter()
        let now = storyNow
        // The banner uppercases the event; Turkish ships pre-uppercased so İ/ı
        // survive the locale-insensitive uppercased().
        let event = localized(
            de: "Ergiebiger Dauerregen",
            en: "Persistent heavy rain",
            tr: "ŞİDDETLİ SÜREKLİ YAĞIŞ"
        )
        let headline = localized(
            de: "Amtliche Warnung vor ergiebigem Dauerregen",
            en: "Warning of persistent heavy rain",
            tr: "ŞİDDETLİ YAĞIŞ UYARISI"
        )
        let description = localized(
            de: "Es tritt ergiebiger Dauerregen auf. Niederschlagsmengen bis 60 l/m² in 12 Stunden. Örtlich sind Überflutungen von Straßen und Unterführungen möglich.",
            en: "Persistent heavy rain is occurring. Precipitation amounts of up to 60 l/m² within 12 hours. Local flooding of roads and underpasses is possible.",
            tr: "Şiddetli ve sürekli yağış bekleniyor. 12 saat içinde metrekareye 60 litreye kadar yağış düşebilir. Yollarda ve alt geçitlerde su baskınları görülebilir."
        )
        let alert: [String: Any] = [
            "alertId": "screenshot.heavy.rain",
            "source": "dwd",
            "event": event,
            "severity": "severe",
            "urgency": "Immediate",
            "certainty": "Likely",
            "responseType": "Prepare",
            "onsetAt": formatter.string(from: now.addingTimeInterval(-2 * 3600)),
            "expiresAt": formatter.string(from: now.addingTimeInterval(10 * 3600)),
            "headline": headline,
            "description": description,
        ]
        return ["alertCount": 1, "alerts": [alert]]
    }

    // MARK: - Radar series (oscar-server /radar/series)

    static func precipSeriesJSON() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        let now = storyNow
        // -30 min … +105 min in 5-minute steps: rain peaking shortly after
        // "now", easing off within the next one and a half hours.
        let series = stride(from: -30, through: 105, by: 5).map { minutes -> [String: Any] in
            let t = Double(minutes)
            // Smooth gaussian humps instead of piecewise lines — the area
            // chart interpolates these into a natural rain curve: the main
            // cell peaking just after "now", a small trailing shower later.
            let value = sunnyStory ? 0 :
                7.4 * exp(-pow((t - 10) / 48, 2)) + 1.9 * exp(-pow((t - 90) / 22, 2))
            return [
                "timestamp": formatter.string(from: now.addingTimeInterval(t * 60)),
                "precipitation": (value * 10).rounded() / 10,
                "is_forecast": minutes > 0,
            ]
        }
        return [
            "source": "dwd",
            "unit": "mm/h",
            "latitude": latitude,
            "longitude": longitude,
            "series": series,
        ]
    }

    // MARK: - Climate archive (archive-api.open-meteo.com)

    /// Daily highs for whatever range the archive service requests: a Berlin-ish
    /// seasonal cycle plus a warming trend, deterministic jitter per day. The
    /// climate section reduces this through the real `ClimateSummary.make`.
    static func archiveJSON(for url: URL) -> [String: Any] {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func date(_ name: String, fallback: Date) -> Date {
            guard let raw = query.first(where: { $0.name == name })?.value,
                  let parsed = dayFormatter.date(from: raw) else { return fallback }
            return parsed
        }
        let calendar = Calendar(identifier: .gregorian)
        let start = date("start_date", fallback: dayFormatter.date(from: "1940-01-01")!)
        let end = date("end_date", fallback: .now)
        let firstYear = 1940
        let lastYear = calendar.component(.year, from: .now)

        var times: [String] = []
        var values: [Double] = []
        var day = start
        while day <= end {
            let year = calendar.component(.year, from: day)
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: day) ?? 1
            let seasonal = 9.5 + 13 * sin(2 * .pi * Double(dayOfYear - 109) / 365)
            let progress = Double(year - firstYear) / Double(max(lastYear - firstYear, 1))
            let trend = pow(progress, 2.0) * 2.6
            let jitter = (Double((year * 373 + dayOfYear * 7919) % 97) / 97.0 - 0.5) * 5.2
            times.append(dayFormatter.string(from: day))
            values.append(((seasonal + trend + jitter) * 10).rounded() / 10)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return [
            "latitude": latitude,
            "longitude": longitude,
            "daily": ["time": times, "temperature_2m_max": values] as [String: Any],
            "daily_units": ["time": "iso8601", "temperature_2m_max": "°C"],
        ]
    }

    // MARK: - Ensemble (ensemble-api.open-meteo.com)

    static func ensembleJSON() -> [String: Any] {
        let dayStart = storyDayStart
        let dayCount = 16
        let memberCount = 30
        let tmax: [Double] = [16, 19, 22, 24, 26, 25, 21, 24, 27, 25, 23, 22, 24, 26, 27, 25]
        let tmin: [Double] = [13, 12, 13, 14, 15, 16, 14, 13, 15, 16, 14, 13, 14, 15, 16, 15]
        let precip: [Double] = [32, 9, 0.5, 0, 0, 0.3, 5, 0, 0, 1, 3, 6, 2, 0, 0, 4]
        let windMax: [Double] = [30, 22, 14, 10, 9, 12, 18, 11, 9, 13, 15, 17, 12, 10, 11, 14]

        var daily: [String: Any] = [
            "time": (0..<dayCount).map {
                dayFormatter.string(from: dayStart.addingTimeInterval(Double($0) * 86_400))
            }
        ]
        for member in 1...memberCount {
            let phase = Double(member) * 1.7
            let suffix = String(format: "member%02d", member)
            func offsets(_ scale: (Int) -> Double) -> [Double] {
                (0..<dayCount).map { day in sin(phase + Double(day) * 0.9) * scale(day) }
            }
            let spread = { (day: Int) in 0.7 + Double(day) * 0.38 }
            daily["temperature_2m_max_\(suffix)"] =
                zip(tmax, offsets(spread)).map { $0 + $1 }
            daily["temperature_2m_min_\(suffix)"] =
                zip(tmin, offsets { spread($0) * 0.8 }).map { $0 + $1 }
            daily["precipitation_sum_\(suffix)"] =
                zip(precip, offsets { 0.4 + Double($0) * 0.9 })
                    .map { max(0, $0 * (1 + sin(phase) * 0.25) + $1) }
            daily["wind_speed_10m_max_\(suffix)"] =
                zip(windMax, offsets { 1.2 + Double($0) * 0.35 }).map { max(4, $0 + $1) }
            daily["wind_speed_10m_min_\(suffix)"] =
                zip(windMax, offsets { 0.8 + Double($0) * 0.25 }).map { max(2, $0 * 0.45 + $1) }
            daily["wind_direction_10m_dominant_\(suffix)"] =
                (0..<dayCount).map { day in 240 + sin(phase + Double(day)) * 25 }
        }

        return [
            "latitude": latitude,
            "longitude": longitude,
            "utc_offset_seconds": TimeZone.current.secondsFromGMT(),
            "timezone": TimeZone.current.identifier,
            "timezone_abbreviation": TimeZone.current.abbreviation() ?? "CEST",
            "daily_units": [
                "time": "iso8601",
                "temperature_2m_min": "°C",
                "temperature_2m_max": "°C",
                "precipitation_sum": "mm",
                "wind_speed_10m_min": "km/h",
                "wind_speed_10m_max": "km/h",
                "wind_direction_10m_dominant": "°",
            ],
            "daily": daily,
        ]
    }

    // MARK: - Member card

    #if !os(watchOS)
    static var stickerPlacements: [MemberCardStickerPlacement] {
        // Kept clear of the left column, where the card prints the member name
        // (top) and the "Beta User" tier (bottom).
        [
            MemberCardStickerPlacement(assetName: "sticker_sun", xRatio: 0.60, yRatio: 0.28, scale: 0.85, rotation: 0.16, zIndex: 1),
            MemberCardStickerPlacement(assetName: "sticker_umbrella", xRatio: 0.58, yRatio: 0.70, scale: 1.0, rotation: -0.2, zIndex: 2),
            MemberCardStickerPlacement(assetName: "sticker_oscar", xRatio: 0.82, yRatio: 0.30, scale: 1.1, rotation: -0.1, zIndex: 3),
            MemberCardStickerPlacement(assetName: "sticker_grumpy_cloud", xRatio: 0.82, yRatio: 0.70, scale: 0.85, rotation: 0.12, zIndex: 4),
        ]
    }
    #endif

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
#endif
