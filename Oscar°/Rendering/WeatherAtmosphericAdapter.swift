//
//  WeatherAtmosphericAdapter.swift
//  Oscar°
//
//  Created by Philipp Bolte on 10/08/25.
//  Adapter to convert weather API data to atmospheric rendering parameters
//

import Foundation
import CoreLocation
import SwiftUI
import simd

/// Converts weather data from APIs into atmospheric rendering parameters
class WeatherAtmosphericAdapter {
    
    private let renderer = AtmosphericRenderer()
    
    // MARK: - Main Interface
    
    /// Generate atmospheric sky gradient from weather data
    /// - Parameters:
    ///   - weather: Current weather data (includes timezone-aware time)
    ///   - location: Location coordinates
    /// - Returns: LinearGradient representing the atmospheric sky
    func generateAtmosphericSkyGradient(
        from weather: Weather,
        at location: CLLocationCoordinate2D
    ) -> LinearGradient {
        
        // Use timezone-aware time from weather data
        let localDate = getLocationAwareDate(from: weather)
        
        // Calculate sun position using timezone-aware calculations
        let sunElevation = renderer.calculateSunElevation(for: localDate, at: location, weather: weather)
        let sunAzimuth   = renderer.calculateSunAzimuth(for: localDate, at: location, weather: weather)
        
        if weather.debug {
            print("🕐 AtmosphericAdapter: Local time: \(localDate)")
            print("🌅 AtmosphericAdapter: Sun elevation: \(sunElevation * 180 / Float.pi)°, azimuth: \(sunAzimuth * 180 / Float.pi)°")
        }
        
        // Convert weather data to atmospheric conditions
        let atmosphericConditions = convertWeatherToAtmosphericConditions(weather)
        
        if weather.debug {
            print("🌦️ AtmosphericAdapter: Conditions - humidity: \(atmosphericConditions.humidity), cloudCover: \(atmosphericConditions.cloudCover)")
        }
        
        // Generate the gradient
        return renderer.generateSkyGradient(
            sunElevation: sunElevation,
            azimuth: sunAzimuth,
            coordinates: location,
            atmosphere: atmosphericConditions,
            weather: weather // Pass weather for sunrise/sunset data
        )
    }
    
    /// Convert the app's timezone-aware time to a proper Date object
    private func getLocationAwareDate(from weather: Weather) -> Date {
        guard let dayBegin = weather.forecast.hourly?.time.first else {
            return Date() // Fallback to current time if no forecast data
        }
        
        // weather.time is a fraction of the day (0.0 = start of day, 1.0 = end of day)
        let currentTimeOffset = weather.time * 86400.0 // seconds
        let utcTimestamp = dayBegin + currentTimeOffset
        let utcDate = Date(timeIntervalSince1970: utcTimestamp)
        
        if weather.debug {
            var calendar = Calendar.current
            calendar.timeZone = TimeZone(secondsFromGMT: weather.forecast.utc_offset_seconds ?? 0) ?? TimeZone.current
            
            let formatter = DateFormatter()
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            
            print("🕐 AtmosphericAdapter: UTC timestamp: \(utcTimestamp)")
            print("🕐 AtmosphericAdapter: UTC Date: \(utcDate)")
            print("🕐 AtmosphericAdapter: Local time display: \(formatter.string(from: utcDate))")
            print("🕐 AtmosphericAdapter: weather.time fraction: \(weather.time)")
            print("🕐 AtmosphericAdapter: dayBegin: \(dayBegin)")
        }
        
        return utcDate
    }
    
    /// Get atmospheric cloud colors for tinting clouds
    func getAtmosphericCloudColor(
        from weather: Weather,
        at location: CLLocationCoordinate2D,
        isTop: Bool
    ) -> Color {
        guard location.latitude != 0 && location.longitude != 0 else {
            return Color(red: 0.6, green: 0.6, blue: 0.6)
        }
        
        let localDate    = getLocationAwareDate(from: weather)
        let sunElevation = renderer.calculateSunElevation(for: localDate, at: location, weather: weather)
        
        // Sample the atmospheric color at cloud level (about 30% up from horizon)
        let cloudViewAngle = Float.pi / 2.0 * 0.3 // 30% up from horizon to zenith
        let viewDirection  = simd_float3(0, cos(cloudViewAngle), sin(cloudViewAngle))
        
        // Get sunrise/sunset data for proper color calculation
        let dayBegin = weather.forecast.hourly?.time.first ?? 0
        let currentTimestamp = dayBegin + (weather.time * 86400.0)
        let (sunriseTime, sunsetTime) = getSunriseSunsetForCurrentTime(weather: weather, currentTimestamp: currentTimestamp)
        
        // Get weather code for realistic cloud coloring
        let weatherCode = Int(weather.forecast.current?.weathercode ?? 0)
        
        // Renderer’s cloud color
        let atmosphericColor = renderer.getAtmosphericColorForClouds(
            viewDirection: viewDirection,
            sunElevation: sunElevation,
            currentTime: currentTimestamp,
            sunrise: sunriseTime,
            sunset: sunsetTime,
            isTopTint: isTop,
            weatherCode: weatherCode
        )
        
        return Color(
            red: Double(atmosphericColor.x),
            green: Double(atmosphericColor.y),
            blue: Double(atmosphericColor.z)
        )
    }
    
    // MARK: - Weather Data Conversion
    
    private func convertWeatherToAtmosphericConditions(_ weather: Weather) -> AtmosphericConditions {
        let currentHumidity       = weather.forecast.hourly?.relativehumidity_2m?.first ?? 50.0
        let currentPrecipitation  = weather.forecast.current?.precipitation ?? 0.0
        let currentCloudCover     = weather.forecast.current?.cloudcover ?? 0.0
        let currentPressure       = weather.forecast.hourly?.pressure_msl?.first ?? 1013.25
        
        let humidity = Float(currentHumidity) / 100.0
        let moisture = calculateMoisture(
            humidity: Float(currentHumidity),
            precipitation: Float(currentPrecipitation),
            radar: weather.radar
        )
        let particleDensity = calculateParticleDensity(
            cloudCover: Float(currentCloudCover),
            weather: weather
        )
        let precipitationIntensity = calculatePrecipitationIntensity(
            precipitation: Float(currentPrecipitation),
            radar: weather.radar
        )
        let cloudCover = Float(currentCloudCover) / 100.0
        let pressure = normalizePressure(Float(currentPressure))
        
        return AtmosphericConditions(
            humidity: humidity,
            moisture: moisture,
            particleDensity: particleDensity,
            precipitationIntensity: precipitationIntensity,
            cloudCover: cloudCover,
            pressure: pressure
        )
    }
    
    // MARK: - Atmospheric Parameter Calculations
    
    private func calculateMoisture(
        humidity: Float,
        precipitation: Float,
        radar: Components.Schemas.RadarResponse
    ) -> Float {
        var moisture = humidity / 100.0
        if precipitation > 0 { moisture = min(1.0, moisture + precipitation * 0.1) }
        if radar.isRaining() {
            let radarIntensity = getRadarPrecipitationIntensity(radar)
            moisture = min(1.0, moisture + radarIntensity * 0.2)
        }
        return moisture
    }
    
    private func calculateParticleDensity(
        cloudCover: Float,
        weather: Weather
    ) -> Float {
        var particles = cloudCover / 100.0
        if let code = weather.forecast.current?.weathercode {
            switch Int(code) {
            case 45, 48: particles = min(1.0, particles + 0.6) // Fog
            case 51...67: particles = min(1.0, particles + 0.3) // Drizzle/Rain
            case 71...86: particles = min(1.0, particles + 0.4) // Snow
            case 95...99: particles = min(1.0, particles + 0.5) // Thunderstorm
            default: break
            }
        }
        return particles
    }
    
    private func calculatePrecipitationIntensity(
        precipitation: Float,
        radar: Components.Schemas.RadarResponse
    ) -> Float {
        var intensity: Float = 0.0
        if precipitation > 0 { intensity = min(1.0, precipitation / 10.0) }
        if radar.isRaining() {
            intensity = max(intensity, getRadarPrecipitationIntensity(radar))
        }
        return intensity
    }
    
    private func normalizePressure(_ pressure: Float) -> Float {
        let normalized = pressure / 1013.25
        return max(0.8, min(1.2, normalized))
    }
    
    // MARK: - Radar Data Helpers
    
    private func getRadarPrecipitationIntensity(_ radar: Components.Schemas.RadarResponse) -> Float {
        guard let radarData = radar.radar?.first,
              let precipData = radarData.precipitation_5 else {
            return 0.0
        }
        var total: Int = 0
        var count: Int = 0
        for row in precipData {
            for cell in row {
                total += cell
                count += 1
            }
        }
        guard count > 0 else { return 0.0 }
        let avg = Float(total) / Float(count)
        return min(1.0, avg / 255.0)
    }
    
    // MARK: - Time-based Enhancements
    
    func isTwilight(for date: Date, at location: CLLocationCoordinate2D, weather: Weather) -> Bool {
        let sunElevation = renderer.calculateSunElevation(for: date, at: location, weather: weather)
        return sunElevation < 0 && sunElevation > -0.314 // -18° in radians
    }
    
    func getTwilightType(for date: Date, at location: CLLocationCoordinate2D, weather: Weather) -> TwilightType {
        let sunElevation = renderer.calculateSunElevation(for: date, at: location, weather: weather)
        if sunElevation >= 0 { return .none }
        if sunElevation > -0.105 { return .civil }
        if sunElevation > -0.21  { return .nautical }
        if sunElevation > -0.314 { return .astronomical }
        return .night
    }
    
    /// Get atmospheric colors for widget backgrounds (top and bottom)
    func getWidgetBackgroundColors(
        from weather: Weather,
        at location: CLLocationCoordinate2D
    ) -> [Color] {
        let gradient = generateAtmosphericSkyGradient(from: weather, at: location)
        
        guard location.latitude != 0 && location.longitude != 0 else {
            return [Color(red: 0.2, green: 0.5, blue: 0.9),
                    Color(red: 0.6, green: 0.8, blue: 0.95)]
        }
        
        let localDate    = getLocationAwareDate(from: weather)
        let sunElevation = renderer.calculateSunElevation(for: localDate, at: location, weather: weather)
        let sunAzimuth   = renderer.calculateSunAzimuth(for: localDate, at: location, weather: weather)
        
        // Sun vector (for consistency if needed later)
        _ = simd_float3(
            cos(sunElevation) * sin(sunAzimuth),
            sin(sunElevation),
            cos(sunElevation) * cos(sunAzimuth)
        )
        
        // Sunrise/sunset for phase
        let dayBegin = weather.forecast.hourly?.time.first ?? 0
        let currentTimestamp = dayBegin + (weather.time * 86400.0)
        let (sunriseTime, sunsetTime) = getSunriseSunsetForCurrentTime(weather: weather, currentTimestamp: currentTimestamp)
        
        let solarPhase = determineSolarPhase(
            currentTime: currentTimestamp,
            sunrise: sunriseTime,
            sunset: sunsetTime,
            sunElevation: sunElevation
        )
        
        // Colors for zenith & horizon using the same palettes/logic as renderer (simplified)
        let zenithDirection  = simd_float3(0, 1, 0)
        let horizonDirection = simd_float3(0, 0, 1)
        
        let zenithSkyColor = calculateSkyColorForView(
            viewDirection: zenithDirection,
            sunElevation: sunElevation,
            solarPhase: solarPhase,
            weather: weather
        )
        let horizonSkyColor = calculateSkyColorForView(
            viewDirection: horizonDirection,
            sunElevation: sunElevation,
            solarPhase: solarPhase,
            weather: weather
        )
        
        return [
            Color(red: Double(zenithSkyColor.x),  green: Double(zenithSkyColor.y),  blue: Double(zenithSkyColor.z)),
            Color(red: Double(horizonSkyColor.x), green: Double(horizonSkyColor.y), blue: Double(horizonSkyColor.z))
        ]
    }
    
    /// Calculate sky color for a specific view direction (helper for widget colors)
    private func calculateSkyColorForView(
        viewDirection: simd_float3,
        sunElevation: Float,
        solarPhase: SolarPhase,
        weather: Weather
    ) -> simd_float3 {
        let horizonFactor = 1.0 - viewDirection.y
        let weatherCode   = Int(weather.forecast.current?.weathercode ?? 0)
        let cloudCover    = Float(weather.forecast.current?.cloudcover ?? 0) / 100.0
        let precipitation = Float(weather.forecast.current?.precipitation ?? 0)
        
        // Base sky color with smooth transitions
        let baseSkyColor = getSmoothSkyColorForPhase(
            solarPhase: solarPhase,
            horizonFactor: horizonFactor,
            sunElevation: sunElevation
        )
        
        return applyWeatherEffectsToSky(
            baseColor: baseSkyColor,
            weatherCode: weatherCode,
            cloudCover: cloudCover,
            precipitationIntensity: precipitation,
            solarPhase: solarPhase,
            horizonFactor: horizonFactor
        )
    }
    
    // MARK: - Phase & Palettes (aligned with renderer)
    
    enum SolarPhase {
        case day, sunrise, sunset, goldenHour, civilTwilight, nauticalTwilight, astronomicalTwilight, night
    }
    
    /// Elevation-driven phase logic with near-sunset guard (degrees)
    private func determineSolarPhase(
        currentTime: Double,
        sunrise: Double,
        sunset: Double,
        sunElevation: Float
    ) -> SolarPhase {
        let elevDeg: Float = sunElevation * 180.0 / .pi
        let civil: Float = -6.0
        let nautical: Float = -12.0
        let astro: Float = -18.0
        
        let minsToSunset = Float((sunset - currentTime) / 60.0)
        if minsToSunset > 0, minsToSunset < 75, elevDeg > -0.833 {
            return elevDeg >= 6 ? .day : .goldenHour
        }
        
        if elevDeg >= 6.0 { return .day }
        if elevDeg >= 0.0 { return .goldenHour }
        if elevDeg >= civil { return .civilTwilight }
        if elevDeg >= nautical { return .nauticalTwilight }
        if elevDeg >= astro { return .astronomicalTwilight }
        return .night
    }
    
    /// Get smooth sky colors with phase transitions for widget
    private func getSmoothSkyColorForPhase(
        solarPhase: SolarPhase,
        horizonFactor: Float,
        sunElevation: Float   // radians
    ) -> simd_float3 {
        
        let elevDeg = sunElevation * 180.0 / .pi
        
        // Get base color for current phase
        var primaryColor = getBaseSkyColorForPhase(
            solarPhase: solarPhase,
            horizonFactor: horizonFactor,
            sunElevation: sunElevation
        )
        
        // Add smooth transitions between phases
        switch solarPhase {
        case .day:
            // Blend towards golden hour as sun gets lower
            if elevDeg < 10.0 && elevDeg > 6.0 {
                let goldenHourColor = getBaseSkyColorForPhase(
                    solarPhase: .goldenHour,
                    horizonFactor: horizonFactor,
                    sunElevation: sunElevation
                )
                let blendFactor = (10.0 - elevDeg) / 4.0
                primaryColor = simd_mix(primaryColor, goldenHourColor, simd_float3(repeating: blendFactor))
            }
            
        case .goldenHour:
            // Blend with day or twilight depending on elevation
            if elevDeg > 3.0 {
                let dayColor = getBaseSkyColorForPhase(
                    solarPhase: .day,
                    horizonFactor: horizonFactor,
                    sunElevation: sunElevation
                )
                let blendFactor = (elevDeg - 3.0) / 3.0
                primaryColor = simd_mix(primaryColor, dayColor, simd_float3(repeating: blendFactor))
            } else if elevDeg > -3.0 {
                let twilightColor = getBaseSkyColorForPhase(
                    solarPhase: .civilTwilight,
                    horizonFactor: horizonFactor,
                    sunElevation: sunElevation
                )
                let blendFactor = (-elevDeg + 3.0) / 6.0
                primaryColor = simd_mix(primaryColor, twilightColor, simd_float3(repeating: blendFactor))
            }
            
        case .civilTwilight:
            // Blend with golden hour when close to horizon
            if elevDeg > -3.0 {
                let goldenHourColor = getBaseSkyColorForPhase(
                    solarPhase: .goldenHour,
                    horizonFactor: horizonFactor,
                    sunElevation: sunElevation
                )
                let blendFactor = (elevDeg + 3.0) / 3.0
                primaryColor = simd_mix(primaryColor, goldenHourColor, simd_float3(repeating: blendFactor))
            }
            
        default:
            break
        }
        
        return primaryColor
    }

    /// Widget/base palettes aligned to renderer; includes twilight→night blend via sunElevation
    private func getBaseSkyColorForPhase(
        solarPhase: SolarPhase,
        horizonFactor: Float,
        sunElevation: Float   // radians
    ) -> simd_float3 {
        
        // Night palette for blends
        let nightZenith  = simd_float3(0.05, 0.08, 0.16)
        let nightHorizon = simd_float3(0.08, 0.10, 0.20)
        // Blend factor: 0 at -18°, 1 at 0°
        let blend = max(0.0, min(1.0, (sunElevation + 0.314) / 0.314))
        
        switch solarPhase {
        case .day:
            // Clear blue sky
            let zenithBlue  = simd_float3(0.20, 0.50, 0.90)
            let horizonBlue = simd_float3(0.60, 0.80, 0.95)
            return simd_mix(zenithBlue, horizonBlue, simd_float3(repeating: horizonFactor))
            
        case .sunrise, .goldenHour:
            // Softer, less yellow (peachy)
            let zenithColor  = simd_float3(0.42, 0.62, 0.90)
            let horizonColor = simd_float3(0.98, 0.78, 0.70)
            return simd_mix(zenithColor, horizonColor, simd_float3(repeating: horizonFactor * 0.8))
            
        case .sunset:
            // Redder due to particle accumulation throughout the day
            let zenithColor  = simd_float3(0.32, 0.44, 0.82)
            let horizonColor = simd_float3(0.95, 0.62, 0.58)  // More red than sunrise
            return simd_mix(zenithColor, horizonColor, simd_float3(repeating: horizonFactor * 0.8))
            
        case .civilTwilight:
            let civilZenith  = simd_float3(0.2, 0.3, 0.5)
            let civilHorizon = simd_float3(0.85, 0.5, 0.35) // warmer orange
            let civilColor   = simd_mix(civilZenith, civilHorizon, simd_float3(repeating: horizonFactor * 0.6))
            let nightBlend   = simd_mix(nightZenith, nightHorizon, simd_float3(repeating: horizonFactor))
            return simd_mix(nightBlend, civilColor, simd_float3(repeating: blend))
            
        case .nauticalTwilight:
            let nautZenith  = simd_float3(0.07, 0.12, 0.38)
            let nautHorizon = simd_float3(0.25, 0.20, 0.35)
            let nautColor   = simd_mix(nautZenith, nautHorizon, simd_float3(repeating: horizonFactor))
            let nightBlend  = simd_mix(nightZenith, nightHorizon, simd_float3(repeating: horizonFactor))
            return simd_mix(nightBlend, nautColor, simd_float3(repeating: blend * 0.6))
            
        case .astronomicalTwilight:
            let astroZenith  = simd_float3(0.06, 0.09, 0.18)
            let astroHorizon = simd_float3(0.10, 0.12, 0.22)
            let astroColor   = simd_mix(astroZenith, astroHorizon, simd_float3(repeating: horizonFactor))
            let nightBlend   = simd_mix(nightZenith, nightHorizon, simd_float3(repeating: horizonFactor))
            return simd_mix(nightBlend, astroColor, simd_float3(repeating: blend * 0.3))
            
        case .night:
            return simd_mix(nightZenith, nightHorizon, simd_float3(repeating: horizonFactor))
        }
    }
    
    /// Apply weather effects to base color (same parameters as renderer’s simplified path)
    private func applyWeatherEffectsToSky(
        baseColor: simd_float3,
        weatherCode: Int,
        cloudCover: Float,
        precipitationIntensity: Float,
        solarPhase: SolarPhase,
        horizonFactor: Float
    ) -> simd_float3 {
        
        var modifiedColor = baseColor
        
        // Thunderstorms
        if weatherCode >= 95 && weatherCode <= 99 {
            if solarPhase != .night && solarPhase != .astronomicalTwilight {
                let stormDarkening: Float = 0.3
                let stormColorShift = simd_float3(0.1, 0.1, 0.0)
                modifiedColor = modifiedColor * stormDarkening + stormColorShift
                let contrastFactor = 1.0 - horizonFactor * 0.5
                modifiedColor = modifiedColor * contrastFactor
            }
        }
        // Heavy rain
        else if weatherCode >= 61 && weatherCode <= 67 {
            if solarPhase != .night && solarPhase != .astronomicalTwilight {
                let rainDarkening: Float = 0.5
                let rainColorShift = simd_float3(-0.05, -0.02, 0.05)
                modifiedColor = modifiedColor * rainDarkening + rainColorShift
            }
        }
        // Light rain / drizzle
        else if weatherCode >= 51 && weatherCode <= 60 {
            if solarPhase != .night && solarPhase != .astronomicalTwilight {
                let drizzleDarkening: Float = 0.7
                let drizzleColorShift = simd_float3(-0.02, 0.0, 0.02)
                modifiedColor = modifiedColor * drizzleDarkening + drizzleColorShift
            }
        }
        
        // Cloud cover effects (dayish phases)
        if cloudCover > 0.1 {
            if solarPhase != .night && solarPhase != .astronomicalTwilight {
                let cloudDarkening = 1.0 - (cloudCover * 0.4)
                let cloudColorShift = simd_float3(-0.1, -0.05, 0.0) * cloudCover
                modifiedColor = modifiedColor * cloudDarkening + cloudColorShift
                
                if cloudCover > 0.8 {
                    let flatteningFactor = 1.0 - (cloudCover - 0.8) * 2.5
                    let gray = (baseColor.x + baseColor.y + baseColor.z) / 3.0
                    let uniformColor = simd_mix(baseColor,
                                                simd_float3(repeating: gray),
                                                simd_float3(repeating: flatteningFactor))
                    modifiedColor = simd_mix(modifiedColor, uniformColor, simd_float3(repeating: 0.6))
                }
            }
        }
        
        return simd_clamp(modifiedColor,
                          simd_float3(repeating: 0.0),
                          simd_float3(repeating: 1.0))
    }
    
    /// Get sunrise and sunset times for the current timestamp (finds the correct day)
    private func getSunriseSunsetForCurrentTime(weather: Weather, currentTimestamp: Double) -> (sunrise: Double, sunset: Double) {
        guard let sunriseArray = weather.forecast.daily?.sunrise,
              let sunsetArray  = weather.forecast.daily?.sunset,
              let dailyTimes   = weather.forecast.daily?.time else {
            return (0, 0)
        }
        
        var calendar = Calendar(identifier: .gregorian)
        if let off = weather.forecast.utc_offset_seconds {
            calendar.timeZone = TimeZone(secondsFromGMT: off) ?? .current
        }
        let currentDate = Date(timeIntervalSince1970: currentTimestamp)
        
        for (index, _) in dailyTimes.enumerated() {
            if index < sunriseArray.count && index < sunsetArray.count {
                let sunriseDate = Date(timeIntervalSince1970: sunriseArray[index])
                if calendar.isDate(currentDate, inSameDayAs: sunriseDate) {
                    if weather.debug {
                        let df = DateFormatter()
                        df.dateFormat = "yyyy-MM-dd HH:mm"
                        df.timeZone = calendar.timeZone
                        print("🌅 WeatherAtmosphericAdapter: Found correct day \(index) for time \(df.string(from: currentDate))")
                        print("   Sunrise: \(df.string(from: sunriseDate))")
                        print("   Sunset: \(df.string(from: Date(timeIntervalSince1970: sunsetArray[index])))")
                    }
                    return (sunriseArray[index], sunsetArray[index])
                }
            }
        }
        
        if weather.debug {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm"
            df.timeZone = calendar.timeZone
            print("⚠️ WeatherAtmosphericAdapter: No matching day found for \(df.string(from: currentDate)), using first day's sunrise/sunset")
        }
        return (sunriseArray.first ?? 0, sunsetArray.first ?? 0)
    }
    
    /// (Kept for future use in adapter if needed)
    func getMoonPhase(for date: Date) -> Float {
        let daysSinceNewMoon = date.timeIntervalSince1970 / 86400.0
        let cyclePosition = (daysSinceNewMoon / 29.53).truncatingRemainder(dividingBy: 1.0)
        return Float(cyclePosition)
    }
}

// MARK: - Supporting Types

enum TwilightType {
    case none        // Sun above horizon
    case civil       // Sun 0° to -6° below horizon
    case nautical    // Sun -6° to -12° below horizon
    case astronomical // Sun -12° to -18° below horizon
    case night       // Sun below -18°
}
