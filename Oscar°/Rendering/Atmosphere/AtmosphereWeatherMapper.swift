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
        let current = weather.forecast.current
        let lowCover: Double = current?.cloudcover_low ?? value(at: hourlyIndex, in: weather.forecast.hourly?.cloudcover_low) ?? 0
        let midCover: Double = current?.cloudcover_mid ?? value(at: hourlyIndex, in: weather.forecast.hourly?.cloudcover_mid) ?? 0
        let highCover: Double = current?.cloudcover_high ?? value(at: hourlyIndex, in: weather.forecast.hourly?.cloudcover_high) ?? 0
        var deck = CloudDeck(
            low: normalized(Float(lowCover), max: 100),
            mid: normalized(Float(midCover), max: 100),
            high: normalized(Float(highCover), max: 100)
        )
        let radarRate = weather.precipSeries?.currentRate.map { Float($0) }
        let modelPrecipitation = Float(value(at: accumulationIndex, in: weather.forecast.hourly?.precipitation)
            ?? weather.forecast.current?.precipitation
            ?? 0)
        let precipitation = radarRate ?? modelPrecipitation
        let snowfall = radarRate.map { $0 * 0.7 }
            ?? Float(value(at: accumulationIndex, in: weather.forecast.hourly?.snowfall) ?? 0)
        let precipitationIntensity = radarRate.map { clamp($0 / 6, 0, 1) }
            ?? clamp(modelPrecipitation / 8, 0, 1)
        if let radarRate, radarRate >= 0.1, condition == .clear || condition == .partlyCloudy || condition == .overcast {
            condition = .rain
            cloudCoverage = max(cloudCoverage, clamp(0.55 + precipitationIntensity * 0.45, 0, 1))
        }
        reconcile(&deck, total: cloudCoverage, condition: condition)
        let windSpeed = Float(weather.forecast.current?.windspeed
            ?? value(at: hourlyIndex, in: weather.forecast.hourly?.windspeed_10m)
            ?? 0)
        let windDirection = Float(weather.forecast.current?.wind_direction_10m
            ?? value(at: hourlyIndex, in: weather.forecast.hourly?.winddirection_10m)
            ?? 0) * .pi / 180

        return finalize(
            utcOffsetSeconds: weather.forecast.utc_offset_seconds ?? 0,
            aqiHaze: airQualityHaze(weather: weather, timestamp: currentTimestamp),
            location: location,
            timestamp: currentTimestamp,
            condition: condition,
            cloudCoverage: cloudCoverage,
            humidity: humidity,
            precipitation: precipitation,
            snowfall: snowfall,
            precipitationIntensity: precipitationIntensity,
            windSpeed: windSpeed,
            windDirection: windDirection,
            deck: deck
        )
    }

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
        let lowCover: Double = interpolatedValue(at: timestamp, times: times, values: hourly?.cloudcover_low) ?? 0
        let midCover: Double = interpolatedValue(at: timestamp, times: times, values: hourly?.cloudcover_mid) ?? 0
        let highCover: Double = interpolatedValue(at: timestamp, times: times, values: hourly?.cloudcover_high) ?? 0
        var deck = CloudDeck(
            low: normalized(Float(lowCover), max: 100),
            mid: normalized(Float(midCover), max: 100),
            high: normalized(Float(highCover), max: 100)
        )

        let radarRate = radarRate(from: weather.precipSeries, at: timestamp)
        let modelPrecipitation = Float(interpolatedValue(at: timestamp, times: times, values: hourly?.precipitation) ?? 0)
        let precipitation = radarRate ?? modelPrecipitation
        let snowfall = radarRate.map { $0 * 0.7 }
            ?? Float(interpolatedValue(at: timestamp, times: times, values: hourly?.snowfall) ?? 0)
        let precipitationIntensity = radarRate.map { clamp($0 / 6, 0, 1) }
            ?? clamp(modelPrecipitation / 8, 0, 1)
        if let radarRate, radarRate >= 0.1, condition == .clear || condition == .partlyCloudy || condition == .overcast {
            condition = .rain
            cloudCoverage = max(cloudCoverage, clamp(0.55 + precipitationIntensity * 0.45, 0, 1))
        }
        reconcile(&deck, total: cloudCoverage, condition: condition)
        let windSpeed = Float(interpolatedValue(at: timestamp, times: times, values: hourly?.windspeed_10m) ?? 0)
        let windDirection = Float(value(at: nearest, in: hourly?.winddirection_10m) ?? 0) * .pi / 180

        return finalize(
            utcOffsetSeconds: weather.forecast.utc_offset_seconds ?? 0,
            aqiHaze: airQualityHaze(weather: weather, timestamp: timestamp),
            location: location,
            timestamp: timestamp,
            condition: condition,
            cloudCoverage: cloudCoverage,
            humidity: humidity,
            precipitation: precipitation,
            snowfall: snowfall,
            precipitationIntensity: precipitationIntensity,
            windSpeed: windSpeed,
            windDirection: windDirection,
            deck: deck
        )
    }

    static func reconcile(_ deck: inout CloudDeck, total: Float, condition: AtmosphereConditionFamily) {
        switch condition {
        case .drizzle, .rain, .freezingRain, .showers, .snow, .thunderstorm:
            deck.low = max(deck.low, total)
        case .clear, .partlyCloudy, .overcast, .fog:
            break
        }
        let peak = max(deck.low, max(deck.mid, deck.high))
        if peak <= 0 {
            deck = CloudDeck(total: total)
        } else if peak < total {
            let factor = total / peak
            deck = CloudDeck(low: min(1, deck.low * factor), mid: min(1, deck.mid * factor), high: min(1, deck.high * factor))
        }
    }

    static func finalize(
        utcOffsetSeconds: Int,
        aqiHaze: Float,
        location: CLLocationCoordinate2D,
        timestamp: Double,
        condition: AtmosphereConditionFamily,
        cloudCoverage: Float,
        humidity: Float,
        precipitation: Float,
        snowfall: Float,
        precipitationIntensity: Float,
        windSpeed: Float,
        windDirection: Float,
        deck: CloudDeck
    ) -> AtmosphereSnapshot {
        let snowfallIntensity = condition == .snow ? max(clamp(snowfall / 6, 0, 1), precipitationIntensity * 0.6) : 0
        let thunderIntensity = condition == .thunderstorm ? max(0.55, precipitationIntensity) : 0
        let sunElevation = solarElevation(
            date: Date(timeIntervalSince1970: timestamp),
            location: location,
            utcOffsetSeconds: utcOffsetSeconds
        )
        let localTimestamp = timestamp + Double(utcOffsetSeconds)
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
            haze: haze,
            turbidity: turbidity,
            windSpeed: clamp(windSpeed / 75, 0, 1),
            windDirection: windDirection,
            aqiHaze: aqiHaze,
            cloudLow: deck.low,
            cloudMid: deck.mid,
            cloudHigh: deck.high
        )
    }

    static func conditionFamily(for code: Int) -> AtmosphereConditionFamily {
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

    static func interpolatedValue(at timestamp: Double, times: [Double], values: [Double]?) -> Double? {
        guard let values, !values.isEmpty, !times.isEmpty else { return nil }
        guard values.count == times.count else {
            return value(at: nearestIndex(to: timestamp, in: times), in: values)
        }
        if timestamp <= times[0] { return values[0] }
        if timestamp >= times[times.count - 1] { return values[values.count - 1] }

        let upper = insertionIndex(for: timestamp, in: times)
        let lower = upper - 1
        let span = times[upper] - times[lower]
        guard span > 0 else { return values[upper] }
        let fraction = (timestamp - times[lower]) / span
        return values[lower] + (values[upper] - values[lower]) * fraction
    }

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

    private static func accumulationIndex(for timestamp: Double, in times: [Double]?) -> Int? {
        guard let times, !times.isEmpty else { return nil }
        return insertionIndex(for: timestamp, in: times)
    }

    private static func nearestIndex(to timestamp: Double, in times: [Double]?) -> Int? {
        guard let times, !times.isEmpty else { return nil }
        let low = insertionIndex(for: timestamp, in: times)
        if low > 0, abs(times[low - 1] - timestamp) <= abs(times[low] - timestamp) {
            return low - 1
        }
        return low
    }

    private static func insertionIndex(for timestamp: Double, in times: [Double]) -> Int {
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
