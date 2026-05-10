import CoreLocation
import Foundation
import simd
import SwiftUI

enum AtmosphereConditionFamily: Float {
    case clear = 0
    case partlyCloudy = 1
    case overcast = 2
    case fog = 3
    case drizzle = 4
    case rain = 5
    case freezingRain = 6
    case snow = 7
    case showers = 8
    case thunderstorm = 9
}

struct AtmosphereSnapshot: Equatable {
    let timestamp: Double
    let timeOfDay: Float
    let sunElevation: Float
    let phase: Float
    let nightAmount: Float
    let condition: AtmosphereConditionFamily
    let cloudCoverage: Float
    let cloudDensity: Float
    let precipitationAmount: Float
    let snowfallAmount: Float
    let precipitationIntensity: Float
    let snowfallIntensity: Float
    let thunderIntensity: Float
    let humidity: Float
    let pressure: Float
    let haze: Float
    let turbidity: Float
    let windSpeed: Float
    let windDirection: Float
    let aqiHaze: Float

    static let fallback = AtmosphereSnapshot(
        timestamp: Date.now.timeIntervalSince1970,
        timeOfDay: 0.5,
        sunElevation: 0.7,
        phase: 1,
        nightAmount: 0,
        condition: .clear,
        cloudCoverage: 0,
        cloudDensity: 0,
        precipitationAmount: 0,
        snowfallAmount: 0,
        precipitationIntensity: 0,
        snowfallIntensity: 0,
        thunderIntensity: 0,
        humidity: 0.5,
        pressure: 1,
        haze: 0.08,
        turbidity: 0.22,
        windSpeed: 0,
        windDirection: 0,
        aqiHaze: 0
    )
}

enum AtmosphereWeatherMapper {
    static func snapshot(from weather: Weather, at location: CLLocationCoordinate2D) -> AtmosphereSnapshot {
        guard location.latitude != 0 || location.longitude != 0 else {
            return .fallback
        }

        let now = Date.now.timeIntervalSince1970
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
        let weatherCode = Int(weather.forecast.current?.weathercode
            ?? value(at: hourlyIndex, in: weather.forecast.hourly?.weathercode)
            ?? 0)
        let condition = conditionFamily(for: weatherCode)
        let cloudCoverage = normalized(
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
        let precipitation = Float(value(at: hourlyIndex, in: weather.forecast.hourly?.precipitation)
            ?? weather.forecast.current?.precipitation
            ?? 0)
        let snowfall = Float(value(at: hourlyIndex, in: weather.forecast.hourly?.snowfall) ?? 0)
        let radarIntensity = radarPrecipitationIntensity(weather.radar)
        let precipitationIntensity = max(
            clamp(precipitation / 8, 0, 1),
            radarIntensity
        )
        let snowfallIntensity = condition == .snow ? max(clamp(snowfall / 6, 0, 1), precipitationIntensity * 0.6) : 0
        let thunderIntensity = condition == .thunderstorm ? max(0.55, precipitationIntensity) : 0
        let windSpeed = Float(weather.forecast.current?.windspeed
            ?? value(at: hourlyIndex, in: weather.forecast.hourly?.windspeed_10m)
            ?? 0)
        let windDirection = Float(weather.forecast.current?.wind_direction_10m
            ?? value(at: hourlyIndex, in: weather.forecast.hourly?.winddirection_10m)
            ?? 0) * .pi / 180
        let aqiHaze = airQualityHaze(weather: weather, timestamp: currentTimestamp)
        let sunElevation = solarElevation(
            date: Date(timeIntervalSince1970: currentTimestamp),
            location: location,
            utcOffsetSeconds: weather.forecast.utc_offset_seconds ?? 0
        )
        let localTimestamp = currentTimestamp + Double(weather.forecast.utc_offset_seconds ?? 0)
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
            timestamp: currentTimestamp,
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

    private static func nearestIndex(to timestamp: Double, in times: [Double]?) -> Int? {
        guard let times, !times.isEmpty else { return nil }
        return times.indices.min { lhs, rhs in
            abs(times[lhs] - timestamp) < abs(times[rhs] - timestamp)
        }
    }

    private static func value(at index: Int?, in values: [Double]?) -> Double? {
        guard let index, let values, values.indices.contains(index) else { return nil }
        return values[index]
    }

    private static func normalized(_ value: Float, max: Float) -> Float {
        clamp(value / max, 0, 1)
    }

    private static func radarPrecipitationIntensity(_ radar: Components.Schemas.RadarResponse) -> Float {
        guard let frame = radar.radar?.first,
              let precipitation = frame.precipitation_5 else {
            return 0
        }

        var total: Float = 0
        var maxValue: Float = 0
        var count: Float = 0

        for row in precipitation {
            for cell in row {
                let value = Float(cell) / 10
                total += value
                maxValue = max(maxValue, value)
                count += 1
            }
        }

        guard count > 0 else { return 0 }
        let average = total / count
        return clamp(max(average / 3, maxValue / 12), 0, 1)
    }

    private static func airQualityHaze(weather: Weather, timestamp: Double) -> Float {
        guard let hourly = weather.air.hourly else { return 0 }
        let index = nearestIndex(to: timestamp, in: hourly.time)
        let pm25 = Float(value(at: index, in: hourly.european_aqi_pm2_5) ?? 0)
        let pm10 = Float(value(at: index, in: hourly.european_aqi_pm10) ?? 0)
        let no2 = Float(value(at: index, in: hourly.european_aqi_no2) ?? 0)
        return clamp(max(pm25, max(pm10, no2)) / 100, 0, 1)
    }

    private static func cloudDensityFor(
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

    private static func solarElevation(
        date: Date,
        location: CLLocationCoordinate2D,
        utcOffsetSeconds: Int
    ) -> Float {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .current

        let day = Float(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let hour = Float(calendar.component(.hour, from: date))
        let minute = Float(calendar.component(.minute, from: date))
        let second = Float(calendar.component(.second, from: date))
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

    private static func daylightPhase(sunElevation: Float) -> Float {
        let degrees = sunElevation * 180 / .pi
        if degrees >= 6 { return 1 }
        if degrees >= 0 { return smoothstep(0, 6, degrees) }
        if degrees >= -6 { return 0.35 * smoothstep(-6, 0, degrees) }
        if degrees >= -18 { return 0.1 * smoothstep(-18, -6, degrees) }
        return 0
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let x = clamp((value - edge0) / (edge1 - edge0), 0, 1)
        return x * x * (3 - 2 * x)
    }

    private static func clamp(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
        min(max(value, lower), upper)
    }
}

enum AtmosphereSampler {
    static func skyGradient(snapshot: AtmosphereSnapshot, sampleCount: Int = 8) -> LinearGradient {
        LinearGradient(
            stops: skyStops(snapshot: snapshot, sampleCount: sampleCount),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func skyStops(snapshot: AtmosphereSnapshot, sampleCount: Int = 8) -> [Gradient.Stop] {
        let count = max(2, sampleCount)
        return (0..<count).map { index in
            let location = Float(index) / Float(count - 1)
            return Gradient.Stop(
                color: color(for: snapshot, horizonFactor: location),
                location: Double(location)
            )
        }
    }

    static func widgetBackgroundColors(snapshot: AtmosphereSnapshot) -> [Color] {
        [
            color(for: snapshot, horizonFactor: 0),
            color(for: snapshot, horizonFactor: 1)
        ]
    }

    static func cloudTopTint(snapshot: AtmosphereSnapshot) -> Color {
        cloudColor(snapshot: snapshot, top: true)
    }

    static func cloudBottomTint(snapshot: AtmosphereSnapshot) -> Color {
        cloudColor(snapshot: snapshot, top: false)
    }

    private static func color(for snapshot: AtmosphereSnapshot, horizonFactor: Float) -> Color {
        let dayZenith = simd_float3(0.20, 0.48, 0.86)
        let dayHorizon = simd_float3(0.68, 0.84, 0.95)
        let goldenZenith = simd_float3(0.38, 0.56, 0.84)
        let goldenHorizon = simd_float3(0.98, 0.66, 0.48)
        let twilightZenith = simd_float3(0.05, 0.08, 0.22)
        let twilightHorizon = simd_float3(0.18, 0.13, 0.34)
        let nightZenith = simd_float3(0.022, 0.040, 0.095)
        let nightHorizon = simd_float3(0.042, 0.052, 0.11)

        let h = smoothstep(0, 1, horizonFactor)
        let day = mix(dayZenith, dayHorizon, t: h)
        let golden = mix(goldenZenith, goldenHorizon, t: h * 0.92)
        let twilight = mix(twilightZenith, twilightHorizon, t: h * 0.60)
        let night = mix(nightZenith, nightHorizon, t: h)

        let elevationDegrees = snapshot.sunElevation * 180 / .pi
        var color: simd_float3
        if elevationDegrees >= 6 {
            color = day
        } else if elevationDegrees >= 0 {
            color = mix(golden, day, t: smoothstep(0, 6, elevationDegrees))
        } else if elevationDegrees >= -6 {
            color = mix(twilight, golden, t: smoothstep(-6, 0, elevationDegrees))
        } else {
            color = mix(night, twilight, t: smoothstep(-18, -6, elevationDegrees))
        }

        let gray = simd_float3(repeating: (color.x + color.y + color.z) / 3)
        color = mix(color, gray, t: snapshot.cloudDensity * 0.38 + snapshot.haze * 0.22)
        color *= 1 - snapshot.precipitationIntensity * 0.36 - snapshot.thunderIntensity * 0.30
        color += simd_float3(0.02, 0.025, 0.035) * snapshot.haze
        if snapshot.snowfallIntensity > 0 {
            color = mix(color, simd_float3(0.72, 0.78, 0.84), t: snapshot.snowfallIntensity * 0.18)
        }

        return rgbColor(clamp(color))
    }

    private static func cloudColor(snapshot: AtmosphereSnapshot, top: Bool) -> Color {
        let base = colorVector(for: color(for: snapshot, horizonFactor: top ? 0.32 : 0.62))
        let nightDim = 1 - snapshot.nightAmount * 0.7
        let bright = (top ? simd_float3(0.92, 0.92, 0.90) : simd_float3(0.54, 0.56, 0.60)) * nightDim
        let storm = (top ? simd_float3(0.42, 0.44, 0.48) : simd_float3(0.15, 0.16, 0.20)) * nightDim
        let rain = mix(bright, storm, t: max(snapshot.precipitationIntensity, snapshot.thunderIntensity))
        let color = mix(bright, rain, t: snapshot.cloudDensity)
        let elevDeg = snapshot.sunElevation * 180 / .pi
        let sunsetProximity = 1 - min(1, abs(min(max(elevDeg, -6), 6)) / 6)
        let tintFactor = 0.28 + snapshot.nightAmount * 0.4 + sunsetProximity * 0.32
        return rgbColor(clamp(mix(color, base, t: tintFactor)))
    }

    private static func colorVector(for color: Color) -> simd_float3 {
        let components = color.getComponents()
        return simd_float3(Float(components.red), Float(components.green), Float(components.blue))
    }

    private static func rgbColor(_ vector: simd_float3) -> Color {
        Color(red: Double(vector.x), green: Double(vector.y), blue: Double(vector.z))
    }

    private static func mix(_ lhs: simd_float3, _ rhs: simd_float3, t: Float) -> simd_float3 {
        simd_mix(lhs, rhs, simd_float3(repeating: min(max(t, 0), 1)))
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let x = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return x * x * (3 - 2 * x)
    }

    private static func clamp(_ vector: simd_float3) -> simd_float3 {
        simd_clamp(vector, simd_float3(repeating: 0), simd_float3(repeating: 1))
    }
}
