import CoreLocation
import Foundation
import simd

enum AtmosphereWeatherMapper {
    @MainActor static func snapshot(
        from weather: Weather,
        at location: CLLocationCoordinate2D,
        for date: Date? = nil
    ) -> AtmosphereSnapshot {
        guard location.latitude != 0 || location.longitude != 0 else {
            return .fallback
        }

        let now = Date.now.timeIntervalSince1970
        // Hourly-detail scrubs render an arbitrary forecast hour. Near "now" the
        // live path below answers (current + radar stay authoritative); further
        // out those sources describe the wrong moment and must not bleed in.
        if let date, abs(date.timeIntervalSince1970 - now) > 900 {
            return scrubbedSnapshot(from: weather, at: location, for: date)
        }
        let forecastTimes = weather.forecast.hourly?.time ?? []
        let currentTimestamp: Double
        if let first = forecastTimes.first, let last = forecastTimes.last, now >= first, now <= last {
            currentTimestamp = now
        } else {
            currentTimestamp = weather.forecast.current?.time
                ?? weather.forecast.hourly?.time.first.map { $0 + weather.time * 86_400 }
                ?? now
        }
        let hourlyIndex = nearestIndex(to: currentTimestamp, in: weather.forecast.hourly?.time)
        let accumulationIndex = accumulationIndex(for: currentTimestamp, in: weather.forecast.hourly?.time)
        let weatherCode = Int(weather.forecast.current?.weathercode
            ?? value(at: hourlyIndex, in: weather.forecast.hourly?.weathercode)
            ?? 0)
        var condition = conditionFamily(for: weatherCode)
        var cloudCoverage = normalized(
            Float(weather.forecast.current?.cloudcover
                  ?? value(at: hourlyIndex, in: weather.forecast.hourly?.cloudcover)
                  ?? 0),
            max: 100
        )
        let humidity = normalized(
            Float(value(at: hourlyIndex, in: weather.forecast.hourly?.relativehumidity_2m) ?? 50),
            max: 100
        )
        let pressure = clamp(
            Float(value(at: hourlyIndex, in: weather.forecast.hourly?.pressure_msl) ?? 1013.25) / 1013.25,
            0.86,
            1.14
        )
        // Precipitation "now": fresh radar wins in both directions — a measured 0
        // is an answer, only nil (no coverage / stale) falls through to the model's
        // current value, then the hourly slot (which smears mid-hour rain onset).
        let radarRate = weather.precipSeries?.currentRate.map { Float($0) }
        // The hourly slot, like the scrubbed path: `current.precipitation` is
        // built from 15-minutely data and reads far lower than the hour's sum.
        let modelPrecipitation = Float(value(at: accumulationIndex, in: weather.forecast.hourly?.precipitation)
            ?? weather.forecast.current?.precipitation
            ?? 0)
        let precipitation = radarRate ?? modelPrecipitation
        // Radar includes snow as liquid equivalent; the 7:1 snow-to-liquid ratio
        // converts its mm/h to the hourly array's cm.
        let snowfall = radarRate.map { $0 * 0.7 }
            ?? Float(value(at: accumulationIndex, in: weather.forecast.hourly?.snowfall) ?? 0)
        // Radar mm/h saturates at ~6; the model's hourly mm at ~8.
        let precipitationIntensity = radarRate.map { clamp($0 / 6, 0, 1) }
            ?? clamp(modelPrecipitation / 8, 0, 1)
        // Radar sees rain the forecast doesn't: a blue, sunny sky can't be right while
        // precipitation reaches the ground. Lift a dry forecast to an overcast, rainy
        // scene so the sky/clouds/sun agree with the rain animation that already shows.
        // Any measurable rate counts (0.1 mm/h is the series' smallest nonzero step) —
        // even drizzle must not fall out of a rendered blue sky.
        if let radarRate, radarRate >= 0.1, condition == .clear || condition == .partlyCloudy || condition == .overcast {
            condition = .rain
            cloudCoverage = max(cloudCoverage, clamp(0.55 + precipitationIntensity * 0.45, 0, 1))
        }
        let windSpeed = Float(weather.forecast.current?.windspeed
            ?? value(at: hourlyIndex, in: weather.forecast.hourly?.windspeed_10m)
            ?? 0)
        let windDirection = Float(weather.forecast.current?.wind_direction_10m
            ?? value(at: hourlyIndex, in: weather.forecast.hourly?.winddirection_10m)
            ?? 0) * .pi / 180

        return finalize(
            weather: weather,
            location: location,
            timestamp: currentTimestamp,
            condition: condition,
            cloudCoverage: cloudCoverage,
            humidity: humidity,
            pressure: pressure,
            precipitation: precipitation,
            snowfall: snowfall,
            precipitationIntensity: precipitationIntensity,
            windSpeed: windSpeed,
            windDirection: windDirection
        )
    }

    /// Scrub path: a snapshot for an arbitrary forecast hour. Hourly values only
    /// — `current` describes now, and the radar nowcast only knows its own span,
    /// so neither may bleed into a scrubbed hour (radar still wins inside that
    /// span, where it genuinely knows the minute). Continuous fields interpolate
    /// between the surrounding hours so the sky doesn't step at hour boundaries
    /// while scrubbing; the weather code (categorical) snaps to the nearest hour.
    @MainActor private static func scrubbedSnapshot(
        from weather: Weather,
        at location: CLLocationCoordinate2D,
        for date: Date
    ) -> AtmosphereSnapshot {
        let hourly = weather.forecast.hourly
        let times = hourly?.time ?? []
        var timestamp = date.timeIntervalSince1970
        if let first = times.first, let last = times.last {
            timestamp = min(max(timestamp, first), last)
        }

        let nearest = nearestIndex(to: timestamp, in: times)
        let weatherCode = Int(value(at: nearest, in: hourly?.weathercode) ?? 0)
        var condition = conditionFamily(for: weatherCode)
        var cloudCoverage = normalized(
            Float(interpolatedValue(at: timestamp, times: times, values: hourly?.cloudcover) ?? 0),
            max: 100
        )
        let humidity = normalized(
            Float(interpolatedValue(at: timestamp, times: times, values: hourly?.relativehumidity_2m) ?? 50),
            max: 100
        )
        let pressure = clamp(
            Float(interpolatedValue(at: timestamp, times: times, values: hourly?.pressure_msl) ?? 1013.25) / 1013.25,
            0.86,
            1.14
        )

        let radarRate = radarRate(from: weather.precipSeries, at: timestamp)
        let modelPrecipitation = Float(interpolatedValue(at: timestamp, times: times, values: hourly?.precipitation) ?? 0)
        let precipitation = radarRate ?? modelPrecipitation
        let snowfall = radarRate.map { $0 * 0.7 }
            ?? Float(interpolatedValue(at: timestamp, times: times, values: hourly?.snowfall) ?? 0)
        let precipitationIntensity = radarRate.map { clamp($0 / 6, 0, 1) }
            ?? clamp(modelPrecipitation / 8, 0, 1)
        // Same sky/rain agreement rule as the live path: measurable radar rain
        // must not fall out of a rendered blue sky.
        if let radarRate, radarRate >= 0.1, condition == .clear || condition == .partlyCloudy || condition == .overcast {
            condition = .rain
            cloudCoverage = max(cloudCoverage, clamp(0.55 + precipitationIntensity * 0.45, 0, 1))
        }
        let windSpeed = Float(interpolatedValue(at: timestamp, times: times, values: hourly?.windspeed_10m) ?? 0)
        // Direction is circular: interpolating across the 360° wrap would swing
        // the drops through the whole rose, so it snaps to the nearest hour.
        let windDirection = Float(value(at: nearest, in: hourly?.winddirection_10m) ?? 0) * .pi / 180

        return finalize(
            weather: weather,
            location: location,
            timestamp: timestamp,
            condition: condition,
            cloudCoverage: cloudCoverage,
            humidity: humidity,
            pressure: pressure,
            precipitation: precipitation,
            snowfall: snowfall,
            precipitationIntensity: precipitationIntensity,
            windSpeed: windSpeed,
            windDirection: windDirection
        )
    }

    /// Shared tail of both mapper paths: everything derived once condition,
    /// coverage, moisture, and precipitation are settled.
    @MainActor private static func finalize(
        weather: Weather,
        location: CLLocationCoordinate2D,
        timestamp: Double,
        condition: AtmosphereConditionFamily,
        cloudCoverage: Float,
        humidity: Float,
        pressure: Float,
        precipitation: Float,
        snowfall: Float,
        precipitationIntensity: Float,
        windSpeed: Float,
        windDirection: Float
    ) -> AtmosphereSnapshot {
        let snowfallIntensity = condition == .snow ? max(clamp(snowfall / 6, 0, 1), precipitationIntensity * 0.6) : 0
        let thunderIntensity = condition == .thunderstorm ? max(0.55, precipitationIntensity) : 0
        let aqiHaze = airQualityHaze(weather: weather, timestamp: timestamp)
        let sunElevation = solarElevation(
            date: Date(timeIntervalSince1970: timestamp),
            location: location,
            utcOffsetSeconds: weather.forecast.utc_offset_seconds ?? 0
        )
        let localTimestamp = timestamp + Double(weather.forecast.utc_offset_seconds ?? 0)
        let timeOfDay = Float(((localTimestamp.truncatingRemainder(dividingBy: 86_400)) + 86_400)
            .truncatingRemainder(dividingBy: 86_400) / 86_400)
        let phase = daylightPhase(sunElevation: sunElevation)
        let nightAmount = 1 - smoothstep(-12, 0, sunElevation * 180 / .pi)
        let cloudDensity = cloudDensityFor(
            condition: condition,
            cloudCoverage: cloudCoverage,
            humidity: humidity,
            precipitation: precipitationIntensity
        )
        let haze = clamp(
            humidity * 0.24
            + cloudCoverage * 0.18
            + precipitationIntensity * 0.28
            + aqiHaze * 0.34
            + (condition == .fog ? 0.65 : 0),
            0,
            1
        )
        let turbidity = clamp(
            0.12
            + humidity * 0.16
            + cloudDensity * 0.24
            + precipitationIntensity * 0.2
            + aqiHaze * 0.28,
            0,
            1
        )

        return AtmosphereSnapshot(
            timestamp: timestamp,
            timeOfDay: timeOfDay,
            sunElevation: sunElevation,
            phase: phase,
            nightAmount: nightAmount,
            condition: condition,
            cloudCoverage: cloudCoverage,
            cloudDensity: cloudDensity,
            precipitationAmount: precipitation,
            snowfallAmount: snowfall,
            precipitationIntensity: precipitationIntensity,
            snowfallIntensity: snowfallIntensity,
            thunderIntensity: thunderIntensity,
            humidity: humidity,
            pressure: pressure,
            haze: haze,
            turbidity: turbidity,
            windSpeed: clamp(windSpeed / 75, 0, 1),
            windDirection: windDirection,
            aqiHaze: aqiHaze
        )
    }

    private static func conditionFamily(for code: Int) -> AtmosphereConditionFamily {
        switch code {
        case 0:
            return .clear
        case 1, 2:
            return .partlyCloudy
        case 3:
            return .overcast
        case 45, 48:
            return .fog
        case 51...57:
            return .drizzle
        case 61...65:
            return .rain
        case 66, 67:
            return .freezingRain
        case 71...77, 85, 86:
            return .snow
        case 80...82:
            return .showers
        case 95...99:
            return .thunderstorm
        default:
            return .overcast
        }
    }

    /// Linear interpolation over an ascending hourly series. Internal (not
    /// private): the hourly detail timeline samples its HUD values with the same
    /// semantics the sim renders.
    static func interpolatedValue(at timestamp: Double, times: [Double], values: [Double]?) -> Double? {
        guard let values, !values.isEmpty, !times.isEmpty else { return nil }
        guard values.count == times.count else {
            return value(at: nearestIndex(to: timestamp, in: times), in: values)
        }
        if timestamp <= times[0] { return values[0] }
        if timestamp >= times[times.count - 1] { return values[values.count - 1] }

        var low = 0
        var high = times.count - 1
        while low < high {
            let mid = (low + high) / 2
            if times[mid] < timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let upper = low
        let lower = low - 1
        let span = times[upper] - times[lower]
        guard span > 0 else { return values[upper] }
        let fraction = (timestamp - times[lower]) / span
        return values[lower] + (values[upper] - values[lower]) * fraction
    }

    /// Radar/nowcast rate at an arbitrary time — only within the series' own
    /// span (± one 5-minute frame): beyond it the radar knows nothing and must
    /// return nil so the model forecast answers instead.
    private static func radarRate(from series: PrecipSeriesResponse?, at timestamp: Double) -> Float? {
        guard let points = series?.series, !points.isEmpty else { return nil }
        var nearest: PrecipPoint?
        var nearestDistance = Double.infinity
        for point in points {
            let distance = abs(point.timestamp.timeIntervalSince1970 - timestamp)
            if distance < nearestDistance {
                nearest = point
                nearestDistance = distance
            }
        }
        guard let nearest, nearestDistance <= 300 else { return nil }
        return Float(nearest.precipitation)
    }

    /// Slot whose accumulation covers `timestamp`: Open-Meteo's hourly sums
    /// (precipitation, snowfall) describe the hour ending at each stamp, so the
    /// first stamp at or after now is the current hour, not the nearest one.
    private static func accumulationIndex(for timestamp: Double, in times: [Double]?) -> Int? {
        guard let times, !times.isEmpty else { return nil }
        var low = 0
        var high = times.count - 1
        while low < high {
            let mid = (low + high) / 2
            if times[mid] < timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private static func nearestIndex(to timestamp: Double, in times: [Double]?) -> Int? {
        guard let times, !times.isEmpty else { return nil }
        // Hourly times are sorted ascending: binary-search the insertion point and pick the
        // closer neighbour — O(log n) instead of an O(n) scan on the per-snapshot path.
        var low = 0
        var high = times.count - 1
        while low < high {
            let mid = (low + high) / 2
            if times[mid] < timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }
        if low > 0, abs(times[low - 1] - timestamp) <= abs(times[low] - timestamp) {
            return low - 1
        }
        return low
    }

    private static func value(at index: Int?, in values: [Double]?) -> Double? {
        guard let index, let values, values.indices.contains(index) else { return nil }
        return values[index]
    }

    private static func normalized(_ value: Float, max: Float) -> Float {
        clamp(value / max, 0, 1)
    }

    @MainActor private static func airQualityHaze(weather: Weather, timestamp: Double) -> Float {
        guard let hourly = weather.air.hourly else { return 0 }
        let index = nearestIndex(to: timestamp, in: hourly.time)
        let pm25 = Float(value(at: index, in: hourly.european_aqi_pm2_5) ?? 0)
        let pm10 = Float(value(at: index, in: hourly.european_aqi_pm10) ?? 0)
        let no2 = Float(value(at: index, in: hourly.european_aqi_no2) ?? 0)
        return clamp(max(pm25, max(pm10, no2)) / 100, 0, 1)
    }

    // Internal (not private): the debug-mode snapshot builder in
    // Debug/AtmosphereDebugSnapshot.swift reuses these derivations so
    // synthetic states match the live mapper.
    static func cloudDensityFor(
        condition: AtmosphereConditionFamily,
        cloudCoverage: Float,
        humidity: Float,
        precipitation: Float
    ) -> Float {
        let conditionBoost: Float
        switch condition {
        case .clear:
            conditionBoost = 0
        case .partlyCloudy:
            conditionBoost = 0.12
        case .overcast:
            conditionBoost = 0.38
        case .fog:
            conditionBoost = 0.62
        case .drizzle, .rain, .freezingRain, .showers:
            conditionBoost = 0.45
        case .snow:
            conditionBoost = 0.36
        case .thunderstorm:
            conditionBoost = 0.72
        }

        return clamp(cloudCoverage * 0.68 + humidity * 0.12 + precipitation * 0.2 + conditionBoost, 0, 1)
    }

    /// Single reusable UTC calendar — the snapshot path runs per frame, so we shift the date by
    /// the offset (below) instead of allocating a calendar with a per-call timezone each time.
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private static func solarElevation(
        date: Date,
        location: CLLocationCoordinate2D,
        utcOffsetSeconds: Int
    ) -> Float {
        // Represent local time by shifting the instant, then read components with the shared UTC calendar.
        let localDate = Date(timeIntervalSince1970: date.timeIntervalSince1970 + Double(utcOffsetSeconds))
        let day = Float(utcCalendar.ordinality(of: .day, in: .year, for: localDate) ?? 1)
        let components = utcCalendar.dateComponents([.hour, .minute, .second], from: localDate)
        let hour = Float(components.hour ?? 0)
        let minute = Float(components.minute ?? 0)
        let second = Float(components.second ?? 0)
        let clockHours = hour + minute / 60 + second / 3600
        let b = 2 * Float.pi * (day - 81) / 364
        let equationOfTime = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)
        let centralMeridian = 15 * Float(utcOffsetSeconds) / 3600
        let solarTime = clockHours + (4 * (Float(location.longitude) - centralMeridian) + equationOfTime) / 60
        let hourAngle = (solarTime - 12) * (.pi / 12)
        let declination = 0.4095 * sin(0.0172 * day - 1.39)
        let latitude = Float(location.latitude) * .pi / 180
        return asin(sin(declination) * sin(latitude) + cos(declination) * cos(latitude) * cos(hourAngle))
    }

    static func daylightPhase(sunElevation: Float) -> Float {
        let degrees = sunElevation * 180 / .pi
        if degrees >= 6 { return 1 }
        if degrees >= 0 { return smoothstep(0, 6, degrees) }
        if degrees >= -6 { return 0.35 * smoothstep(-6, 0, degrees) }
        if degrees >= -18 { return 0.1 * smoothstep(-18, -6, degrees) }
        return 0
    }

    static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let x = clamp((value - edge0) / (edge1 - edge0), 0, 1)
        return x * x * (3 - 2 * x)
    }

    static func clamp(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
        min(max(value, lower), upper)
    }
}
