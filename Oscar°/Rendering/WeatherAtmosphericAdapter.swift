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
        let sunAzimuth = renderer.calculateSunAzimuth(for: localDate, at: location, weather: weather)
        
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
        let currentTimeOffset = weather.time * 86400.0 // Convert to seconds
        let utcTimestamp = dayBegin + currentTimeOffset
        
        // Create Date from UTC timestamp - the sun calculation will handle timezone conversion
        let utcDate = Date(timeIntervalSince1970: utcTimestamp)
        
        if weather.debug {
            // Create timezone-aware calendar for display
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
    /// - Parameters:
    ///   - weather: Current weather data
    ///   - location: Location coordinates
    ///   - isTop: Whether this is for top or bottom cloud tinting
    /// - Returns: Color for cloud tinting
    func getAtmosphericCloudColor(
        from weather: Weather,
        at location: CLLocationCoordinate2D,
        isTop: Bool
    ) -> Color {
        guard location.latitude != 0 && location.longitude != 0 else {
            // Fallback to neutral cloud color if no location
            return Color(red: 0.6, green: 0.6, blue: 0.6)
        }
        
        let localDate = getLocationAwareDate(from: weather)
        let sunElevation = renderer.calculateSunElevation(for: localDate, at: location, weather: weather)
        
        // Sample the atmospheric color at cloud level (about 30% up from horizon)
        let cloudViewAngle = Float.pi / 2.0 * 0.3 // 30% up from horizon to zenith
        let viewDirection = simd_float3(0, cos(cloudViewAngle), sin(cloudViewAngle))
        
        // Get sunrise/sunset data for proper color calculation
        let sunriseTime = weather.forecast.daily?.sunrise?.first ?? 0
        let sunsetTime = weather.forecast.daily?.sunset?.first ?? 0
        let dayBegin = weather.forecast.hourly?.time.first ?? 0
        let currentTimestamp = dayBegin + (weather.time * 86400.0)
        
        // Get weather code for realistic cloud coloring
        let weatherCode = Int(weather.forecast.current?.weathercode ?? 0)
        
        // Get the atmospheric renderer's color calculation
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
    
    /// Convert Weather object to AtmosphericConditions
    private func convertWeatherToAtmosphericConditions(_ weather: Weather) -> AtmosphericConditions {
        
        // Extract current weather values with safe defaults
        let currentHumidity = weather.forecast.hourly?.relativehumidity_2m?.first ?? 50.0
        let currentPrecipitation = weather.forecast.current?.precipitation ?? 0.0
        let currentCloudCover = weather.forecast.current?.cloudcover ?? 0.0
        let currentPressure = weather.forecast.hourly?.pressure_msl?.first ?? 1013.25
        
        // Calculate atmospheric conditions
        let humidity = Float(currentHumidity) / 100.0 // Convert percentage to 0-1
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
        
        let cloudCover = Float(currentCloudCover) / 100.0 // Convert percentage to 0-1
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
    
    /// Calculate atmospheric moisture from humidity, precipitation, and radar
    private func calculateMoisture(
        humidity: Float,
        precipitation: Float,
        radar: Components.Schemas.RadarResponse
    ) -> Float {
        var moisture = humidity / 100.0 // Base moisture from humidity
        
        // Increase moisture with precipitation
        if precipitation > 0 {
            moisture = min(1.0, moisture + precipitation * 0.1)
        }
        
        // Increase moisture if radar shows precipitation
        if radar.isRaining() {
            let radarIntensity = getRadarPrecipitationIntensity(radar)
            moisture = min(1.0, moisture + radarIntensity * 0.2)
        }
        
        return moisture
    }
    
    /// Calculate particle density from cloud cover and atmospheric conditions
    private func calculateParticleDensity(
        cloudCover: Float,
        weather: Weather
    ) -> Float {
        var particles = cloudCover / 100.0 // Base particles from clouds
        
        // Increase particles in certain weather conditions
        if let weatherCode = weather.forecast.current?.weathercode {
            switch Int(weatherCode) {
            case 45, 48: // Fog
                particles = min(1.0, particles + 0.6)
            case 51...67: // Drizzle/Rain
                particles = min(1.0, particles + 0.3)
            case 71...86: // Snow
                particles = min(1.0, particles + 0.4)
            case 95...99: // Thunderstorm
                particles = min(1.0, particles + 0.5)
            default:
                break
            }
        }
        
        return particles
    }
    
    /// Calculate precipitation intensity from direct measurement and radar
    private func calculatePrecipitationIntensity(
        precipitation: Float,
        radar: Components.Schemas.RadarResponse
    ) -> Float {
        var intensity: Float = 0.0
        
        // From direct precipitation measurement
        if precipitation > 0 {
            intensity = min(1.0, precipitation / 10.0) // Normalize assuming max 10mm/h
        }
        
        // From radar data
        if radar.isRaining() {
            let radarIntensity = getRadarPrecipitationIntensity(radar)
            intensity = max(intensity, radarIntensity)
        }
        
        return intensity
    }
    
    /// Normalize atmospheric pressure to 0.8-1.2 range
    private func normalizePressure(_ pressure: Float) -> Float {
        // Standard pressure: 1013.25 hPa
        // Range typically: 950-1050 hPa
        let normalized = pressure / 1013.25
        return max(0.8, min(1.2, normalized))
    }
    
    // MARK: - Radar Data Helpers
    
    /// Extract precipitation intensity from radar data
    private func getRadarPrecipitationIntensity(_ radar: Components.Schemas.RadarResponse) -> Float {
        guard let radarData = radar.radar?.first,
              let precipData = radarData.precipitation_5 else {
            return 0.0
        }
        
        // Calculate average precipitation intensity from the data grid
        var totalPrecip: Int = 0
        var cellCount: Int = 0
        
        for row in precipData {
            for cell in row {
                totalPrecip += cell
                cellCount += 1
            }
        }
        
        guard cellCount > 0 else { return 0.0 }
        
        let averageIntensity = Float(totalPrecip) / Float(cellCount)
        
        // Normalize to 0-1 range (assuming max radar value of 255)
        return min(1.0, averageIntensity / 255.0)
    }
    
    // MARK: - Time-based Enhancements
    
    /// Check if it's currently twilight period
    func isTwilight(for date: Date, at location: CLLocationCoordinate2D, weather: Weather) -> Bool {
        let sunElevation = renderer.calculateSunElevation(for: date, at: location, weather: weather)
        return sunElevation < 0 && sunElevation > -0.314 // -18 degrees in radians
    }
    
    /// Get twilight type (civil, nautical, astronomical)
    func getTwilightType(for date: Date, at location: CLLocationCoordinate2D, weather: Weather) -> TwilightType {
        let sunElevation = renderer.calculateSunElevation(for: date, at: location, weather: weather)
        
        if sunElevation >= 0 {
            return .none
        } else if sunElevation > -0.105 { // -6 degrees
            return .civil
        } else if sunElevation > -0.21 { // -12 degrees
            return .nautical
        } else if sunElevation > -0.314 { // -18 degrees
            return .astronomical
        } else {
            return .night
        }
    }
    
    /// Get atmospheric colors for widget backgrounds (top and bottom)
    /// - Parameters:
    ///   - weather: Current weather data
    ///   - location: Location coordinates
    /// - Returns: Array with [topColor, bottomColor] for widget gradient
    func getWidgetBackgroundColors(
        from weather: Weather,
        at location: CLLocationCoordinate2D
    ) -> [Color] {
        // Generate full atmospheric gradient and extract top/bottom colors
        let gradient = generateAtmosphericSkyGradient(from: weather, at: location)
        
        // We need to extract the actual sky colors, not use the gradient directly
        // Let's recreate the sky color calculation for zenith and horizon
        guard location.latitude != 0 && location.longitude != 0 else {
            // Fallback to day sky colors if no location
            return [Color(red: 0.2, green: 0.5, blue: 0.9), Color(red: 0.6, green: 0.8, blue: 0.95)]
        }
        
        let localDate = getLocationAwareDate(from: weather)
        let sunElevation = renderer.calculateSunElevation(for: localDate, at: location, weather: weather)
        let sunAzimuth = renderer.calculateSunAzimuth(for: localDate, at: location, weather: weather)
        
        // Calculate sun position vector
        let sunPosition = simd_float3(
            cos(sunElevation) * sin(sunAzimuth),
            sin(sunElevation), 
            cos(sunElevation) * cos(sunAzimuth)
        )
        
        // Get sunrise/sunset data for solar phase determination
        let sunriseTime = weather.forecast.daily?.sunrise?.first ?? 0
        let sunsetTime = weather.forecast.daily?.sunset?.first ?? 0
        let dayBegin = weather.forecast.hourly?.time.first ?? 0
        let currentTimestamp = dayBegin + (weather.time * 86400.0)
        
        let solarPhase = determineSolarPhase(
            currentTime: currentTimestamp,
            sunrise: sunriseTime,
            sunset: sunsetTime,
            sunElevation: sunElevation
        )
        
        // Calculate sky colors for zenith (top) and horizon (bottom)
        let zenithDirection = simd_float3(0, 1, 0)  // Looking straight up
        let horizonDirection = simd_float3(0, 0, 1) // Looking at horizon
        
        let zenithSkyColor = calculateSkyColorForView(
            viewDirection: zenithDirection,
            sunDirection: sunPosition,
            sunElevation: sunElevation,
            solarPhase: solarPhase,
            weather: weather
        )
        
        let horizonSkyColor = calculateSkyColorForView(
            viewDirection: horizonDirection,
            sunDirection: sunPosition,
            sunElevation: sunElevation,
            solarPhase: solarPhase,
            weather: weather
        )
        
        return [
            Color(red: Double(zenithSkyColor.x), green: Double(zenithSkyColor.y), blue: Double(zenithSkyColor.z)),
            Color(red: Double(horizonSkyColor.x), green: Double(horizonSkyColor.y), blue: Double(horizonSkyColor.z))
        ]
    }
    
    /// Calculate sky color for a specific view direction (helper for widget colors)
    private func calculateSkyColorForView(
        viewDirection: simd_float3,
        sunDirection: simd_float3,
        sunElevation: Float,
        solarPhase: SolarPhase,
        weather: Weather
    ) -> simd_float3 {
        let horizonFactor = 1.0 - viewDirection.y // How close to horizon (0 = zenith, 1 = horizon)
        let weatherCode = Int(weather.forecast.current?.weathercode ?? 0)
        let cloudCover = Float(weather.forecast.current?.cloudcover ?? 0) / 100.0
        let precipitation = Float(weather.forecast.current?.precipitation ?? 0)
        
        // Get base sky color for solar phase
        let baseSkyColor = getBaseSkyColorForPhase(solarPhase: solarPhase, horizonFactor: horizonFactor)
        
        // Apply weather effects
        return applyWeatherEffectsToSky(
            baseColor: baseSkyColor,
            weatherCode: weatherCode,
            cloudCover: cloudCover,
            precipitationIntensity: precipitation,
            solarPhase: solarPhase,
            horizonFactor: horizonFactor
        )
    }
    
    /// Helper to determine solar phase (copied from AtmosphericRenderer)
    private func determineSolarPhase(currentTime: Double, sunrise: Double, sunset: Double, sunElevation: Float) -> SolarPhase {
        let civilTwilightAngle: Float = -0.105  // -6 degrees
        let nauticalTwilightAngle: Float = -0.21 // -12 degrees
        let astronomicalTwilightAngle: Float = -0.314 // -18 degrees
        
        // Time-based checks for sunrise/sunset periods (±30 minutes)
        let sunriseWindow = abs(currentTime - sunrise) < 1800 // 30 minutes
        let sunsetWindow = abs(currentTime - sunset) < 1800   // 30 minutes
        
        if sunElevation > 0.05 { // Sun well above horizon
            if sunriseWindow {
                return .sunrise
            } else if sunsetWindow {
                return .sunset
            } else {
                return .day
            }
        } else if sunElevation > civilTwilightAngle {
            return sunriseWindow || sunsetWindow ? .goldenHour : .civilTwilight
        } else if sunElevation > nauticalTwilightAngle {
            return .nauticalTwilight
        } else if sunElevation > astronomicalTwilightAngle {
            return .astronomicalTwilight
        } else {
            return .night
        }
    }
    
    /// Helper to get base sky colors (copied from AtmosphericRenderer)
    private func getBaseSkyColorForPhase(solarPhase: SolarPhase, horizonFactor: Float) -> simd_float3 {
        switch solarPhase {
        case .day:
            // Clear blue sky
            let zenithBlue = simd_float3(0.2, 0.5, 0.9)
            let horizonBlue = simd_float3(0.6, 0.8, 0.95)
            return simd_mix(zenithBlue, horizonBlue, simd_float3(repeating: horizonFactor))
            
        case .sunrise, .goldenHour:
            // Warm sunrise/golden hour colors
            let zenithColor = simd_float3(0.4, 0.6, 0.9)  // Light blue
            let horizonColor = simd_float3(1.0, 0.7, 0.3) // Golden orange
            return simd_mix(zenithColor, horizonColor, simd_float3(repeating: horizonFactor * 0.8))
            
        case .sunset:
            // Warm sunset colors
            let zenithColor = simd_float3(0.3, 0.4, 0.8)  // Deep blue
            let horizonColor = simd_float3(1.0, 0.5, 0.2) // Deep orange/red
            return simd_mix(zenithColor, horizonColor, simd_float3(repeating: horizonFactor))
            
        case .civilTwilight:
            // Blue hour
            let zenithColor = simd_float3(0.1, 0.2, 0.6)
            let horizonColor = simd_float3(0.8, 0.4, 0.3)
            return simd_mix(zenithColor, horizonColor, simd_float3(repeating: horizonFactor * 0.5))
            
        case .nauticalTwilight, .astronomicalTwilight:
            // Twilight colors
            let zenithColor = simd_float3(0.05, 0.1, 0.4)
            let horizonColor = simd_float3(0.2, 0.15, 0.3)
            return simd_mix(zenithColor, horizonColor, simd_float3(repeating: horizonFactor))
            
        case .night:
            // Night sky - darkened for better cloud contrast
            let darkNightBlue = simd_float3(0.05, 0.08, 0.16)   // Darker blue at zenith
            let horizonNight = simd_float3(0.08, 0.10, 0.20)    // Slightly lighter blue at horizon
            return simd_mix(darkNightBlue, horizonNight, simd_float3(repeating: horizonFactor))
        }
    }
    
    /// Helper to apply weather effects (copied from AtmosphericRenderer)
    private func applyWeatherEffectsToSky(
        baseColor: simd_float3,
        weatherCode: Int,
        cloudCover: Float,
        precipitationIntensity: Float,
        solarPhase: SolarPhase,
        horizonFactor: Float
    ) -> simd_float3 {
        
        var modifiedColor = baseColor
        
        // Storm effects - dramatic darkening and color shifts (day only)
        if weatherCode >= 95 && weatherCode <= 99 { // Thunderstorms
            if solarPhase != .night && solarPhase != .astronomicalTwilight {
                let stormDarkening: Float = 0.3 // Make much darker
                let stormColorShift = simd_float3(0.1, 0.1, 0.0) // Slightly greenish tint
                modifiedColor = modifiedColor * stormDarkening + stormColorShift
                
                // Add dramatic contrast - darker sky, but preserve some horizon brightness
                let contrastFactor = 1.0 - horizonFactor * 0.5
                modifiedColor = modifiedColor * contrastFactor
            }
        }
        // Heavy rain effects
        else if weatherCode >= 61 && weatherCode <= 67 { // Heavy rain
            if solarPhase != .night && solarPhase != .astronomicalTwilight {
                let rainDarkening: Float = 0.5 // Moderate darkening
                let rainColorShift = simd_float3(-0.05, -0.02, 0.05) // Slightly blue-gray tint
                modifiedColor = modifiedColor * rainDarkening + rainColorShift
            }
        }
        // Light rain/drizzle effects
        else if weatherCode >= 51 && weatherCode <= 60 { // Light rain/drizzle
            if solarPhase != .night && solarPhase != .astronomicalTwilight {
                let drizzleDarkening: Float = 0.7 // Mild darkening
                let drizzleColorShift = simd_float3(-0.02, 0.0, 0.02) // Slight blue tint
                modifiedColor = modifiedColor * drizzleDarkening + drizzleColorShift
            }
        }
        
        // Cloud cover effects (day only)
        if cloudCover > 0.1 {
            if solarPhase != .night && solarPhase != .astronomicalTwilight {
                // Day: normal cloud effects
                let cloudDarkening = 1.0 - (cloudCover * 0.4) // Up to 40% darkening for full cloud cover
                let cloudColorShift = simd_float3(-0.1, -0.05, 0.0) * cloudCover // Grayish tint
                modifiedColor = modifiedColor * cloudDarkening + cloudColorShift
                
                // Heavy overcast - very flat, uniform lighting (day only)
                if cloudCover > 0.8 {
                    let flatteningFactor = 1.0 - (cloudCover - 0.8) * 2.5
                    let uniformColor = simd_mix(baseColor, simd_float3(repeating: (baseColor.x + baseColor.y + baseColor.z) / 3.0), simd_float3(repeating: flatteningFactor))
                    modifiedColor = simd_mix(modifiedColor, uniformColor, simd_float3(repeating: 0.6))
                }
            }
        }
        
        // Ensure colors stay within valid range
        return simd_clamp(modifiedColor, simd_float3(repeating: 0.0), simd_float3(repeating: 1.0))
    }
    
    enum SolarPhase {
        case day, sunrise, sunset, goldenHour, civilTwilight, nauticalTwilight, astronomicalTwilight, night
    }
    
    /// Calculate moon phase for enhanced night rendering (future enhancement)
    func getMoonPhase(for date: Date) -> Float {
        // Simplified moon phase calculation
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

