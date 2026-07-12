//
//  ScreenshotFixtures.swift
//  Oscar°
//
//  Wire-format payloads served by ScreenshotFixtureServer: a heavy-rain "now"
//  that clears into a warm week, with matching air quality, a severe-rain
//  alert, a dramatic radar series, a warming climate archive, and a widening
//  ensemble. Hourly data anchors to the launch hour so "now"-relative views
//  line up; the values themselves never change between runs.
//

import Foundation
import ImageIO
import UIKit

enum ScreenshotFixtures {
    static let latitude = 51.3397
    static let longitude = 12.3731

    /// The forecast scene tells a different story than the rest of the set:
    /// a sunny summer day instead of the heavy-rain "now".
    private static var sunnyStory: Bool { ScreenshotMode.scene == .nowForecast }

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
        let now = Date.now
        let dayStart = calendar.startOfDay(for: now)
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
        let dayStart = Calendar.current.startOfDay(for: .now)
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

    // MARK: - Alerts (api.brightsky.dev)

    static func alertsJSON() -> [String: Any] {
        if sunnyStory { return ["alerts": [] as [Any]] }
        let formatter = ISO8601DateFormatter()
        let now = Date.now
        let event = localized(
            de: "Ergiebiger Dauerregen",
            en: "Persistent heavy rain",
            tr: "Şiddetli sürekli yağış"
        )
        // The banner strips "Amtliche" and uppercases; Turkish ships
        // pre-uppercased so İ/ı survive the locale-insensitive uppercased().
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
            "id": 1,
            "alert_id": "screenshot.heavy.rain",
            "effective": formatter.string(from: now.addingTimeInterval(-2 * 3600)),
            "onset": formatter.string(from: now.addingTimeInterval(-2 * 3600)),
            "expires": formatter.string(from: now.addingTimeInterval(10 * 3600)),
            "category": "met",
            "response_type": "Prepare",
            "urgency": "Immediate",
            "severity": "severe",
            "certainty": "Likely",
            "event_code": 61,
            "event_en": event,
            "event_de": event,
            "headline_en": headline,
            "headline_de": headline,
            "description_en": description,
            "description_de": description,
        ]
        return ["alerts": [alert]]
    }

    // MARK: - Radar series (oscar-server /radar/series)

    static func precipSeriesJSON() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        let now = Date.now
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
        let dayStart = Calendar.current.startOfDay(for: .now)
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

// MARK: - Synthetic radar (oscar-server frames/grid/tiles/motion/cells)

/// Deterministic fake precipitation for the map and widget scenes: a SW→NE
/// frontal band with embedded convective cores over Leipzig, built from
/// hash-based value noise (structure modeled on the OPERA composite). The
/// same field feeds the fullscreen map's value grid, the widget's raster
/// tiles, and the motion arrows, advected per frame so the timeline animates.
enum SyntheticRadar {
    static let north = 55.6, south = 46.0, west = 3.6, east = 17.8
    /// Served frames mirror the DWD RV timeline oscar-server relays from
    /// Bright Sky: the observed past hour plus pre-extrapolated forecast
    /// frames two hours out, all in 5-minute steps. The key encodes the offset.
    static let offsets = Array(stride(from: -60, through: 120, by: 5))
    static let gridWidth = 280, gridHeight = 240

    static func key(_ offset: Int) -> String { "fx\(offset)" }
    static func offsetMinutes(fromKey key: String) -> Double? {
        key.hasPrefix("fx") ? Double(key.dropFirst(2)) : nil
    }

    // MARK: JSON endpoints

    static func framesJSON() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        let now = Date.now
        let bounds: [String: Any] = ["north": north, "south": south, "west": west, "east": east]
        return [
            "generated_at": formatter.string(from: now),
            "frame_count": offsets.count,
            "frames": offsets.enumerated().map { index, offset in
                [
                    "key": key(offset),
                    "timestamp": formatter.string(from: now.addingTimeInterval(Double(offset) * 60)),
                    "source": "dwd",
                    "index": index,
                    "is_forecast": offset > 0,
                ]
            },
            "bounds": bounds,
            "image_bounds": bounds,
        ]
    }

    static func cellsJSON() -> [String: Any] {
        ["type": "FeatureCollection", "features": [] as [Any]]
    }

    /// One shared coarse flow field, SW→NE like the band's advection.
    static func motionJSON() -> [String: Any] {
        let cols = 8, rows = 8
        var values = [Int16](repeating: 70, count: cols * rows)          // u: east (×0.05 px/step)
        values.append(contentsOf: [Int16](repeating: -40, count: cols * rows))  // v: north
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        let pairs: [[String: Any]] = (0..<(offsets.count - 1)).map {
            ["from": key(offsets[$0]), "to": key(offsets[$0 + 1]), "field": 0, "gap_minutes": 5]
        }
        return [
            "cols": cols, "rows": rows,
            "overview_width": gridWidth, "overview_height": gridHeight,
            "scale": 0.05, "step_minutes": 5,
            "fields": [data.base64EncodedString()],
            "pairs": pairs,
        ]
    }

    // MARK: Field

    private static func hash(_ x: Int, _ y: Int) -> Double {
        var v = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        v ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F
        v = (v ^ (v >> 31)) &* 0xD6E8_FEB8_6659_FD93
        v ^= v >> 32
        return Double(v % 1_000_000) / 1_000_000
    }

    private static func valueNoise(_ x: Double, _ y: Double) -> Double {
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
        let a = hash(x0, y0), b = hash(x0 + 1, y0)
        let c = hash(x0, y0 + 1), d = hash(x0 + 1, y0 + 1)
        return a + (b - a) * smooth(fx) + (c - a) * smooth(fy)
            + (a - b - c + d) * smooth(fx) * smooth(fy)
    }

    private static func fbm(_ x: Double, _ y: Double) -> Double {
        var amplitude = 0.5, frequency = 1.0, total = 0.0
        for _ in 0..<4 {
            total += amplitude * valueNoise(x * frequency, y * frequency)
            amplitude *= 0.5
            frequency *= 2.1
        }
        return total
    }

    /// Intensity 0…1 at a coordinate, advected SW→NE over time.
    static func intensity(lat: Double, lon: Double, minutes t: Double) -> Double {
        let ax = lon - t * 0.011
        let ay = lat - t * 0.006
        let d = ((ay - 51.1) - (ax - 12.4) * 0.55) / 1.9
        let along = (ax - 12.4) * 0.876 + (ay - 51.1) * 0.481
        let envelope = exp(-d * d) * exp(-pow(along / 5.0, 2))
        let n1 = fbm(ax * 1.1 + 40, ay * 1.1 - 7)
        let warp = fbm(ax * 2.3 - 11, ay * 2.3 + 23)
        let n2 = fbm(ax * 3.1 + warp * 1.7 + 90, ay * 3.1 + warp * 1.7 - 55)
        let core = max(0, n1 * 0.55 + n2 * 0.65 - 0.52) * 2.4
        let scattered = max(0, n2 - 0.72) * 1.8
        return min(1, envelope * core + scattered * 0.35)
    }

    // MARK: Mercator helpers

    private static func mercY(_ lat: Double) -> Double {
        log(tan(.pi / 4 + lat * .pi / 360))
    }
    private static func latFromMercY(_ y: Double) -> Double {
        (2 * atan(exp(y)) - .pi / 2) * 180 / .pi
    }

    // MARK: Value grid (fullscreen map's Metal layer)

    /// URLProtocol loads on arbitrary threads — guard the render caches.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var gridCache: [String: Data] = [:]

    /// Single-channel 8-bit grid in Web Mercator rows (row 0 = north), like the
    /// server's lossless WebP — `UIImage(data:)` decodes PNG just the same.
    /// Plain style: 0 = dry, values over the plasma dBZ ramp. Typed: rain span
    /// 1…153 (a July scene has no snow or ice).
    static func gridPNG(frameKey: String, typed: Bool) -> Data {
        let cacheKey = "\(frameKey)|\(typed)"
        cacheLock.lock()
        if let cached = gridCache[cacheKey] { cacheLock.unlock(); return cached }
        cacheLock.unlock()
        let t = offsetMinutes(fromKey: frameKey) ?? 0
        let w = gridWidth, h = gridHeight
        var pixels = [UInt8](repeating: 0, count: w * h)
        let mN = mercY(north), mS = mercY(south)
        for j in 0..<h {
            let lat = latFromMercY(mN + (mS - mN) * Double(j) / Double(h))
            for i in 0..<w {
                let lon = west + (east - west) * Double(i) / Double(w)
                let v = intensity(lat: lat, lon: lon, minutes: t)
                guard v >= 0.02 else { continue }
                pixels[j * w + i] = typed
                    ? UInt8(1 + min(152, v * 152))
                    : UInt8(1 + min(219, v * 219))
            }
        }
        let png = grayPNG(pixels: pixels, width: w, height: h)
        cacheLock.lock()
        gridCache[cacheKey] = png
        cacheLock.unlock()
        return png
    }

    private static func grayPNG(pixels: [UInt8], width: Int, height: Int) -> Data {
        var pixels = pixels
        let image = pixels.withUnsafeMutableBytes { raw -> CGImage? in
            let context = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
            return context?.makeImage()
        }
        guard let image else { return Data() }
        return UIImage(cgImage: image).pngData() ?? Data()
    }

    // MARK: Raster tiles (widget composite + precip gate)

    nonisolated(unsafe) private static var tileCache: [String: Data] = [:]

    /// The widget reverse-maps tile colors to palette indices through the
    /// server colormap (data-space smoothing), so tile pixels must BE palette
    /// entries — hand-approximated colors snap to wrong (purple) indices.
    /// Colormaps pass through the fixture server live; fetch the real plasma
    /// palette once and build tiles from it with the exact grid index math,
    /// which makes the widget match the fullscreen map by construction.
    nonisolated(unsafe) private static var cachedPalette: [UInt8]?
    private static func plasmaPalette() -> [UInt8] {
        cacheLock.lock()
        if let cached = cachedPalette { cacheLock.unlock(); return cached }
        cacheLock.unlock()
        final class Box: @unchecked Sendable { var data: [UInt8]? }
        let box = Box()
        if let url = URL(string: "\(radarBaseURL)/colormaps/plasma") {
            let semaphore = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data, data.count >= 256 * 4 { box.data = [UInt8](data.prefix(256 * 4)) }
                semaphore.signal()
            }.resume()
            _ = semaphore.wait(timeout: .now() + 10)
        }
        // Offline fallback: approximated plasma with a hard alpha ramp.
        let resolved = box.data ?? (0..<256).flatMap { i -> [UInt8] in
            guard i > 0 else { return [0, 0, 0, 0] }
            let t = Double(i - 1) / 254
            let (r, g, b) = plasma(t)
            return [UInt8(r), UInt8(g), UInt8(b), UInt8(min(235, 70 + t * 400))]
        }
        cacheLock.lock()
        cachedPalette = resolved
        cacheLock.unlock()
        return resolved
    }

    /// Raster tile like the server's: the value grid's palette index per
    /// pixel, colorized through the shared colormap (premultiplied).
    static func tilePNG(frameKey: String, z: Int, x: Int, y: Int) -> Data {
        let cacheKey = "\(frameKey)|\(z)/\(x)/\(y)"
        cacheLock.lock()
        if let cached = tileCache[cacheKey] { cacheLock.unlock(); return cached }
        cacheLock.unlock()
        let t = offsetMinutes(fromKey: frameKey) ?? 0
        let palette = plasmaPalette()
        let size = 256
        let n = pow(2.0, Double(z))
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for j in 0..<size {
            let yTile = (Double(y) + Double(j) / Double(size)) / n
            let lat = latFromMercY(.pi * (1 - 2 * yTile))
            for i in 0..<size {
                let lon = (Double(x) + Double(i) / Double(size)) / n * 360 - 180
                let v = intensity(lat: lat, lon: lon, minutes: t)
                guard v >= 0.02 else { continue }
                // Same index math as gridPNG, so tiles == fullscreen grid.
                let index = Int(1 + min(219, v * 219))
                let p = index * 4
                let o = (j * size + i) * 4
                // Straight (non-premultiplied) palette RGBA, exactly like the
                // server's tiles: PNG stores unpremultiplied, and the widget's
                // reverse LUT expects pixels that ARE palette entries.
                pixels[o] = palette[p]
                pixels[o + 1] = palette[p + 1]
                pixels[o + 2] = palette[p + 2]
                pixels[o + 3] = palette[p + 3]
            }
        }
        // Encode via ImageIO from a non-premultiplied CGImage — a CGContext
        // round-trip would premultiply and lose the exact palette values.
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent),
              let png = pngData(from: image) else {
            return Data()
        }
        cacheLock.lock()
        tileCache[cacheKey] = png
        cacheLock.unlock()
        return png
    }

    private static func pngData(from image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func plasma(_ v: Double) -> (Int, Int, Int) {
        let stops: [(Double, (Double, Double, Double))] = [
            (0.00, (13, 8, 135)), (0.25, (126, 3, 168)), (0.50, (204, 71, 120)),
            (0.75, (248, 149, 64)), (1.00, (240, 249, 33)),
        ]
        for i in 0..<(stops.count - 1) {
            let (a, ca) = stops[i], (b, cb) = stops[i + 1]
            if v <= b {
                let f = (v - a) / (b - a)
                return (Int(ca.0 + (cb.0 - ca.0) * f), Int(ca.1 + (cb.1 - ca.1) * f), Int(ca.2 + (cb.2 - ca.2) * f))
            }
        }
        return (240, 249, 33)
    }
}
