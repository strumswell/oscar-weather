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

    /// A calm, clear twilight with visible stars. Used as the backdrop before any forecast
    /// has loaded — first launch, or a cold-start fetch failure — instead of a flat gradient.
    /// Deep civil twilight (sun ≈ 8° below the horizon): a blue dusk sky with the stars out
    /// and no clouds, wind, or precipitation.
    static let twilight = AtmosphereSnapshot(
        timestamp: Date.now.timeIntervalSince1970,
        timeOfDay: 0.9,
        sunElevation: -0.14,
        phase: 0,
        nightAmount: 0.78,
        condition: .clear,
        cloudCoverage: 0,
        cloudDensity: 0,
        precipitationAmount: 0,
        snowfallAmount: 0,
        precipitationIntensity: 0,
        snowfallIntensity: 0,
        thunderIntensity: 0,
        humidity: 0.45,
        pressure: 1,
        haze: 0.05,
        turbidity: 0.18,
        windSpeed: 0,
        windDirection: 0,
        aqiHaze: 0
    )
}

extension AtmosphereSnapshot {
    /// Visibility of the drawn sun DISC: 1 in daylight, fading out as the sun
    /// approaches the horizon, 0 once it dips below. Distinct from `phase`,
    /// which deliberately keeps ambient light through twilight — gating the
    /// disc on `phase` used to float a faint sun in a twilight sky.
    var sunDiscVisibility: Float {
        AtmosphereWeatherMapper.smoothstep(0, 4, sunElevation * 180 / .pi)
    }
}

enum AtmosphereWeatherMapper {
    @MainActor static func snapshot(from weather: Weather, at location: CLLocationCoordinate2D) -> AtmosphereSnapshot {
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
        let precipitation = Float(value(at: hourlyIndex, in: weather.forecast.hourly?.precipitation)
            ?? weather.forecast.current?.precipitation
            ?? 0)
        let snowfall = Float(value(at: hourlyIndex, in: weather.forecast.hourly?.snowfall) ?? 0)
        // Radar rate (mm/h) at the frame nearest "now"; ~6 mm/h maps to full intensity.
        let radarRate = Float(weather.precipSeries?.currentRate ?? 0)
        let radarIntensity = clamp(radarRate / 6, 0, 1)
        let precipitationIntensity = max(
            clamp(precipitation / 8, 0, 1),
            radarIntensity
        )
        // Radar sees rain the forecast doesn't: a blue, sunny sky can't be right while
        // precipitation reaches the ground. Lift a dry forecast to an overcast, rainy
        // scene so the sky/clouds/sun agree with the rain animation that already shows.
        // Any measurable rate counts (0.1 mm/h is the series' smallest nonzero step) —
        // even drizzle must not fall out of a rendered blue sky.
        if radarRate >= 0.1, condition == .clear || condition == .partlyCloudy || condition == .overcast {
            condition = .rain
            cloudCoverage = max(cloudCoverage, clamp(0.55 + radarIntensity * 0.45, 0, 1))
        }
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
            // The effective amount driving the scene: radar-measured rain counts even
            // when the forecast still reads dry (mm and mm/h share the hourly scale).
            precipitationAmount: max(precipitation, radarRate),
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
    nonisolated(unsafe) private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
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

    /// Card wash for the Now stack: a milky, darkened sample of the lower sky,
    /// laid over the cards' frosted material so they share the scene's hue
    /// instead of the material's fixed gray.
    static func cardFill(snapshot: AtmosphereSnapshot) -> Color {
        // Blended by hand: Color.mix needs iOS 18, and this file also builds
        // in targets with older deployment floors.
        var base = colorVector(for: color(for: snapshot, horizonFactor: 1))
        // The frost underneath grays the wash out; push the sample away from
        // its gray axis first so the hue survives the material.
        let gray = simd_float3(repeating: luminance(base))
        base = gray + (base - gray) * 1.7
        // Always darker than the sky it samples: the card sits under the
        // scene instead of glowing over it, in every condition.
        base *= 0.7
        // Except near black: lift dark scenes slightly so night cards still
        // separate from the sky. The squared falloff keeps days untouched.
        let lift = 0.12 * (1 - luminance(base)) * (1 - luminance(base))
        base += simd_float3(repeating: lift)
        base = simd_clamp(base, simd_float3(repeating: 0), simd_float3(repeating: 1))
        return Color(
            red: Double(base.x),
            green: Double(base.y),
            blue: Double(base.z)
        ).opacity(0.65)
    }

    static func cloudTopTint(snapshot: AtmosphereSnapshot, moonGlow: Float = 0) -> Color {
        cloudColor(snapshot: snapshot, top: true, moonGlow: moonGlow)
    }

    static func cloudBottomTint(snapshot: AtmosphereSnapshot, moonGlow: Float = 0) -> Color {
        cloudColor(snapshot: snapshot, top: false, moonGlow: moonGlow)
    }

    private static func color(for snapshot: AtmosphereSnapshot, horizonFactor: Float) -> Color {
        let dayZenith = simd_float3(0.20, 0.48, 0.86)
        let dayHorizon = simd_float3(0.68, 0.84, 0.95)
        let goldenZenith = simd_float3(0.38, 0.56, 0.84)
        let goldenHorizon = simd_float3(0.98, 0.66, 0.48)
        let twilightZenith = simd_float3(0.06, 0.11, 0.28)
        // Blue hour: deep cobalt, not warm plum (ozone Chappuis absorption).
        let twilightHorizon = simd_float3(0.14, 0.26, 0.52)
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
            color = mix(twilight, golden, t: smoothstep(-4, 0, elevationDegrees))
        } else {
            color = mix(night, twilight, t: smoothstep(-16, -6, elevationDegrees))
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

    private static func cloudColor(snapshot: AtmosphereSnapshot, top: Bool, moonGlow: Float) -> Color {
        let base = colorVector(for: color(for: snapshot, horizonFactor: top ? 0.32 : 0.62))
        // Bright-moon nights dim the clouds less ("silver lining").
        let nightDim = 1 - snapshot.nightAmount * (0.7 - 0.25 * moonGlow)
        let bright = (top ? simd_float3(0.92, 0.92, 0.90) : simd_float3(0.54, 0.56, 0.60)) * nightDim
        var storm = (top ? simd_float3(0.42, 0.44, 0.48) : simd_float3(0.15, 0.16, 0.20)) * nightDim
        // Severe storms drift toward teal — the real "green sky" of
        // hail-heavy cells. It's a daytime phenomenon, shows mainly in the
        // bright cloud body, and ordinary thunderstorms stay grey
        // (thunderIntensity floors at 0.55 for any thunderstorm code).
        let severity = max(0, (snapshot.thunderIntensity - 0.55) / 0.45)
        let stormDaylight = 1 - snapshot.nightAmount
        let tealStrength = severity * stormDaylight * (top ? 0.5 : 0.15)
        storm = mix(storm, simd_float3(0.28, 0.40, 0.42) * nightDim, t: tealStrength)
        let rain = mix(bright, storm, t: max(snapshot.precipitationIntensity, snapshot.thunderIntensity))
        var cloud = mix(bright, rain, t: snapshot.cloudDensity)

        let elevDeg = snapshot.sunElevation * 180 / .pi
        let sunsetProximity = 1 - min(1, abs(min(max(elevDeg, -6), 6)) / 6)
        // Golden hour lights clouds from below: warm bottoms, cool blue-grey
        // tops. Heavy decks block the low sun, so the effect fades with
        // density and rain.
        let underlight = sunsetProximity * (1 - max(snapshot.precipitationIntensity, snapshot.cloudDensity * 0.7))
        if top {
            cloud = mix(cloud, simd_float3(0.46, 0.48, 0.62), t: underlight * 0.40)
        } else {
            cloud = mix(cloud, simd_float3(0.99, 0.62, 0.40), t: underlight * 0.65)
        }

        // Less sky-mixing at sunset than before, so the warm light survives.
        let tintFactor = 0.28 + snapshot.nightAmount * 0.4 + sunsetProximity * 0.12
        var result = mix(cloud, base, t: tintFactor)

        // Never let the cloud melt into the sky behind it.
        let sky = colorVector(for: color(for: snapshot, horizonFactor: 0.45))
        let separation: Float = 0.06
        let difference = luminance(result) - luminance(sky)
        if abs(difference) < separation {
            let direction: Float = difference >= 0 ? 1 : -1
            result += simd_float3(repeating: direction * (separation - abs(difference)))
        }

        return rgbColor(clamp(result))
    }

    private static func luminance(_ color: simd_float3) -> Float {
        color.x * 0.299 + color.y * 0.587 + color.z * 0.114
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
