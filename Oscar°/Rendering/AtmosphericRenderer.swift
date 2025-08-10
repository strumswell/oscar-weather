//
//  AtmosphericRenderer.swift
//  Oscar°
//
//  Created by Philipp BolteNo on 10/08/25.
//  Physics-based atmospheric scattering renderer
//

import SwiftUI
import simd
import CoreLocation

/// Physically-based atmospheric renderer using Rayleigh and Mie scattering
/// Based on "A Scalable and Production Ready Sky and Atmosphere Rendering Technique" by Sébastien Hillaire
/// and "Production Sky Rendering" by Andrew Helmer
@Observable
class AtmosphericRenderer {
    
    // MARK: - Physical Constants
    
    /// Earth's radius in meters
    static let earthRadius: Float = 6_371_000.0
    
    /// Atmosphere height in meters
    static let atmosphereHeight: Float = 80_000.0
    
    /// Rayleigh scattering coefficients for RGB wavelengths (680nm, 550nm, 450nm)
    static let rayleighCoefficients = simd_float3(5.8e-6, 1.35e-5, 3.31e-5)
    
    /// Mie scattering coefficient (wavelength independent)
    static let mieCoefficient: Float = 2.0e-5
    
    /// Rayleigh scale height
    static let rayleighScaleHeight: Float = 8000.0
    
    /// Mie scale height
    static let mieScaleHeight: Float = 1200.0
    
    /// Sun angular diameter in radians
    static let sunAngularDiameter: Float = 0.0093
    
    // MARK: - Computed Properties
    
    private var sunPosition = simd_float3(0, 1, 0)
    private var atmosphereParams = AtmosphereParams()
    
    // MARK: - Atmosphere Parameters
    
    struct AtmosphereParams {
        var turbidity: Float = 2.0
        var mieDirectionalG: Float = 0.8
        var sunIntensity: Float = 1000.0
        var mieCoefficient: Float = 0.005
        var rayleighCoefficient: Float = 1.0
    }
    
    // MARK: - Public Interface
    
    /// Generate atmospheric gradient for given conditions
    /// - Parameters:
    ///   - sunElevation: Solar elevation angle in radians (-π/2 to π/2)
    ///   - azimuth: Solar azimuth angle in radians
    ///   - coordinates: Location coordinates
    ///   - atmosphere: Atmospheric conditions (humidity, pressure, particles)
    ///   - weather: Weather data for sunrise/sunset times
    /// - Returns: LinearGradient representing the sky
    func generateSkyGradient(
        sunElevation: Float,
        azimuth: Float,
        coordinates: CLLocationCoordinate2D,
        atmosphere: AtmosphericConditions,
        weather: Weather
    ) -> LinearGradient {
        
        // Update atmospheric parameters based on weather
        updateAtmosphereParams(from: atmosphere)
        
        // Calculate sun position vector
        sunPosition = calculateSunPosition(elevation: sunElevation, azimuth: azimuth)
        
        // Generate gradient stops for different view angles
        let gradientStops = generateGradientStops(
            sunElevation: sunElevation, 
            weather: weather
        )
        
        return LinearGradient(
            stops: gradientStops,
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - Sun Position Calculations
    
    /// Calculate sun position vector from elevation and azimuth
    private func calculateSunPosition(elevation: Float, azimuth: Float) -> simd_float3 {
        let x = cos(elevation) * sin(azimuth)
        let y = sin(elevation)
        let z = cos(elevation) * cos(azimuth)
        return simd_float3(x, y, z)
    }
    
    /// Calculate solar elevation angle from time and location
    func calculateSunElevation(for date: Date, at coordinates: CLLocationCoordinate2D, weather: Weather) -> Float {
        // Create timezone-aware calendar
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: weather.forecast.utc_offset_seconds ?? 0) ?? TimeZone.current
        
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        
        let latitude = Float(coordinates.latitude) * Float.pi / 180.0
        let declination = calculateSolarDeclination(dayOfYear: dayOfYear)
        let hourAngle = calculateHourAngle(hour: hour, minute: minute)
        
        let elevation = asin(
            sin(declination) * sin(latitude) +
            cos(declination) * cos(latitude) * cos(hourAngle)
        )
        
        return elevation
    }
    
    /// Calculate solar azimuth angle from time and location
    func calculateSunAzimuth(for date: Date, at coordinates: CLLocationCoordinate2D, weather: Weather) -> Float {
        // Create timezone-aware calendar
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: weather.forecast.utc_offset_seconds ?? 0) ?? TimeZone.current
        
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        
        let latitude = Float(coordinates.latitude) * Float.pi / 180.0
        let declination = calculateSolarDeclination(dayOfYear: dayOfYear)
        let hourAngle = calculateHourAngle(hour: hour, minute: minute)
        
        let azimuth = atan2(
            sin(hourAngle),
            cos(hourAngle) * sin(latitude) - tan(declination) * cos(latitude)
        )
        
        return azimuth
    }
    
    /// Get atmospheric color for cloud tinting based on lighting conditions
    func getAtmosphericColorForClouds(
        viewDirection: simd_float3,
        sunElevation: Float,
        currentTime: Double,
        sunrise: Double,
        sunset: Double,
        isTopTint: Bool,
        weatherCode: Int
    ) -> simd_float3 {
        
        let solarPhase = determineSolarPhase(
            currentTime: currentTime,
            sunrise: sunrise,
            sunset: sunset,
            sunElevation: sunElevation
        )
        
        // Determine if weather is stormy/rainy
        let isStorm = weatherCode >= 95 && weatherCode <= 99 // Thunderstorms
        let isRain = weatherCode >= 51 && weatherCode <= 67  // Rain/drizzle
        let isHeavyClouds = weatherCode >= 2 // Partly/very cloudy
        
        return calculateRealisticCloudColor(
            solarPhase: solarPhase,
            sunElevation: sunElevation,
            isTopTint: isTopTint,
            isStorm: isStorm,
            isRain: isRain,
            isHeavyClouds: isHeavyClouds
        )
    }
    
    /// Calculate realistic cloud colors based on weather and lighting
    private func calculateRealisticCloudColor(
        solarPhase: SolarPhase,
        sunElevation: Float,
        isTopTint: Bool,
        isStorm: Bool,
        isRain: Bool,
        isHeavyClouds: Bool
    ) -> simd_float3 {
        
        // Storm clouds - dark and dramatic
        if isStorm {
            let darkGray = simd_float3(0.2, 0.2, 0.25) // Dark storm clouds
            let lightGray = simd_float3(0.4, 0.4, 0.45) // Lighter storm clouds
            
            switch solarPhase {
            case .sunrise, .sunset:
                // Storm clouds with warm light breaking through
                let stormBase = isTopTint ? lightGray : darkGray
                let warmTint = simd_float3(0.3, 0.15, 0.1) // Warm orange glow
                return simd_mix(stormBase, stormBase + warmTint, simd_float3(repeating: 0.3))
            default:
                return isTopTint ? lightGray : darkGray
            }
        }
        
        // Rain clouds - higher contrast against rainy sky
        if isRain {
            let rainGray = simd_float3(0.65, 0.65, 0.7)      // Lighter for contrast
            let darkRainGray = simd_float3(0.25, 0.25, 0.3)  // Much darker bottoms
            
            switch solarPhase {
            case .sunrise, .sunset:
                // Rain clouds with subtle warm tinting
                let rainBase = isTopTint ? rainGray : darkRainGray
                let subtleWarm = simd_float3(0.1, 0.05, 0.0)
                return rainBase + subtleWarm
            case .night, .astronomicalTwilight:
                // Night rain clouds - slightly lighter for mobile visibility
                return isTopTint ?
                    simd_float3(0.22, 0.22, 0.26) :   // Slightly lighter gray tops
                    simd_float3(0.14, 0.14, 0.18)     // Slightly lighter bottoms
            default:
                return isTopTint ? rainGray : darkRainGray
            }
        }
        
        // Heavy clouds - light gray
        if isHeavyClouds {
            switch solarPhase {
            case .sunrise, .goldenHour:
                // Warm golden light on clouds
                return isTopTint ? 
                    simd_float3(1.0, 0.9, 0.7) :  // Golden-tinted cloud tops
                    simd_float3(0.8, 0.75, 0.6)   // Warmer shadowed bottoms
                    
            case .sunset:
                // Dramatic sunset colors on clouds
                return isTopTint ?
                    simd_float3(1.0, 0.7, 0.4) :  // Bright orange-red tops
                    simd_float3(0.6, 0.4, 0.3)    // Deep shadowed bottoms
                    
            case .night, .astronomicalTwilight:
                // Night clouds - slightly lighter for mobile visibility
                return isTopTint ?
                    simd_float3(0.22, 0.22, 0.26) :   // Slightly lighter gray tops
                    simd_float3(0.14, 0.14, 0.18)     // Slightly lighter bottoms
                    
            case .civilTwilight, .nauticalTwilight:
                // Twilight clouds with subtle blue
                return isTopTint ?
                    simd_float3(0.3, 0.35, 0.5) :   // Blue-gray tops
                    simd_float3(0.2, 0.2, 0.3)      // Darker blue bottoms
                    
            default: // Day
                // Light gray daytime clouds
                return isTopTint ?
                    simd_float3(0.9, 0.9, 0.9) :    // Light gray tops
                    simd_float3(0.7, 0.7, 0.75)     // Medium gray bottoms
            }
        }
        
        // Clear sky - clouds should be white/very light
        switch solarPhase {
        case .sunrise, .goldenHour:
            // Bright white clouds with golden highlights
            return isTopTint ?
                simd_float3(1.0, 0.95, 0.8) :   // Warm white tops
                simd_float3(0.95, 0.9, 0.8)     // Slightly shadowed warm bottoms
                
        case .sunset:
            // Brilliant sunset clouds
            return isTopTint ?
                simd_float3(1.0, 0.8, 0.5) :    // Bright golden tops
                simd_float3(0.9, 0.7, 0.5)      // Warm shadowed bottoms
                
        case .night, .astronomicalTwilight:
            // Night clouds - slightly lighter for mobile visibility
            return isTopTint ?
                simd_float3(0.22, 0.22, 0.26) :   // Slightly lighter gray tops
                simd_float3(0.14, 0.14, 0.18)     // Slightly lighter bottoms
                
        case .civilTwilight, .nauticalTwilight:
            // Twilight clouds
            return isTopTint ?
                simd_float3(0.4, 0.4, 0.6) :    // Blue-gray
                simd_float3(0.25, 0.25, 0.35)   // Darker blue-gray
                
        default: // Clear day
            // Bright white fluffy clouds
            return isTopTint ?
                simd_float3(1.0, 1.0, 1.0) :    // Pure white tops
                simd_float3(0.9, 0.9, 0.9)      // Very light gray bottoms
        }
    }
    
    private func calculateSolarDeclination(dayOfYear: Int) -> Float {
        return 0.4095 * sin(0.01721 * Float(dayOfYear) - 1.39)
    }
    
    private func calculateHourAngle(hour: Int, minute: Int) -> Float {
        let solarTime = Float(hour) + Float(minute) / 60.0
        return (solarTime - 12.0) * Float.pi / 12.0
    }
    
    // MARK: - Atmospheric Scattering
    
    /// Generate gradient stops by sampling the sky at different view angles
    private func generateGradientStops(sunElevation: Float, weather: Weather) -> [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        let sampleCount = 12
        
        // Get sunrise/sunset times from weather data
        let sunriseTime = weather.forecast.daily?.sunrise?.first ?? 0
        let sunsetTime = weather.forecast.daily?.sunset?.first ?? 0
        let dayBegin = weather.forecast.hourly?.time.first ?? 0
        
        // Determine solar phase based on current time and sunrise/sunset
        let currentTimestamp = dayBegin + (weather.time * 86400.0)
        let solarPhase = determineSolarPhase(
            currentTime: currentTimestamp,
            sunrise: sunriseTime,
            sunset: sunsetTime,
            sunElevation: sunElevation
        )
        
        // Get weather conditions for sky modification
        let weatherCode = Int(weather.forecast.current?.weathercode ?? 0)
        let cloudCover = Float(weather.forecast.current?.cloudcover ?? 0) / 100.0
        let precipitation = Float(weather.forecast.current?.precipitation ?? 0)
        
        // Debug logging
        if weather.debug {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm"
            let currentDate = Date(timeIntervalSince1970: currentTimestamp)
            let sunriseDate = Date(timeIntervalSince1970: sunriseTime)
            let sunsetDate = Date(timeIntervalSince1970: sunsetTime)
            
            print("🌅 Sky Debug:")
            print("  Current time: \(dateFormatter.string(from: currentDate))")
            print("  Sunrise: \(dateFormatter.string(from: sunriseDate))")
            print("  Sunset: \(dateFormatter.string(from: sunsetDate))")
            print("  Sun elevation: \(sunElevation * 180 / Float.pi)°")
            print("  Solar phase: \(solarPhase)")
            print("  Weather code: \(weatherCode)")
            print("  Cloud cover: \(cloudCover * 100)%")
        }
        
        // Generate colors based on solar phase and atmospheric physics
        for i in 0..<sampleCount {
            let viewAngle = Float.pi / 2.0 * Float(i) / Float(sampleCount - 1) // 0 to π/2 (zenith to horizon)
            let viewDirection = simd_float3(0, cos(viewAngle), sin(viewAngle))
            
            let skyColor = calculateSkyColorForPhase(
                viewDirection: viewDirection,
                sunDirection: sunPosition,
                sunElevation: sunElevation,
                solarPhase: solarPhase,
                horizonFactor: Float(i) / Float(sampleCount - 1),
                weatherCode: weatherCode,
                cloudCover: cloudCover,
                precipitationIntensity: precipitation
            )
            
            stops.append(Gradient.Stop(
                color: Color(
                    red: Double(skyColor.x),
                    green: Double(skyColor.y), 
                    blue: Double(skyColor.z)
                ),
                location: Double(i) / Double(sampleCount - 1)
            ))
        }
        
        return stops
    }
    
    /// Determine the current solar phase for proper color transitions
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
    
    /// Calculate sky color based on solar phase and weather conditions
    private func calculateSkyColorForPhase(
        viewDirection: simd_float3,
        sunDirection: simd_float3,
        sunElevation: Float,
        solarPhase: SolarPhase,
        horizonFactor: Float,
        weatherCode: Int = 0,
        cloudCover: Float = 0.0,
        precipitationIntensity: Float = 0.0
    ) -> simd_float3 {
        
        // Get base sky color for solar phase
        let baseSkyColor = getBaseSkyColorForPhase(solarPhase: solarPhase, horizonFactor: horizonFactor)
        
        // Apply weather modifications
        return applyWeatherEffectsToSky(
            baseColor: baseSkyColor,
            weatherCode: weatherCode,
            cloudCover: cloudCover,
            precipitationIntensity: precipitationIntensity,
            solarPhase: solarPhase,
            horizonFactor: horizonFactor
        )
    }
    
    /// Get base sky colors without weather effects
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
            return calculateTwilightSkyColor(
                viewDirection: simd_float3(0, cos(Float.pi / 2.0 * horizonFactor), sin(Float.pi / 2.0 * horizonFactor)),
                sunDirection: sunPosition,
                sunElevation: -0.21 // Approximate nautical twilight angle
            )
            
        case .night:
            // Visually appealing night sky - darkened for better cloud contrast
            let darkNightBlue = simd_float3(0.05, 0.08, 0.16)   // Darker blue at zenith
            let horizonNight = simd_float3(0.08, 0.10, 0.20)    // Slightly lighter blue at horizon
            return simd_mix(darkNightBlue, horizonNight, simd_float3(repeating: horizonFactor))
        }
    }
    
    /// Apply weather effects to sky color
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
            // No darkening during night - preserve base night sky colors
        }
        // Heavy rain effects
        else if weatherCode >= 61 && weatherCode <= 67 { // Heavy rain
            if solarPhase != .night && solarPhase != .astronomicalTwilight {
                let rainDarkening: Float = 0.5 // Moderate darkening
                let rainColorShift = simd_float3(-0.05, -0.02, 0.05) // Slightly blue-gray tint
                modifiedColor = modifiedColor * rainDarkening + rainColorShift
            }
            // No darkening during night - preserve base night sky colors
        }
        // Light rain/drizzle effects
        else if weatherCode >= 51 && weatherCode <= 60 { // Light rain/drizzle
            if solarPhase != .night && solarPhase != .astronomicalTwilight {
                let drizzleDarkening: Float = 0.7 // Mild darkening
                let drizzleColorShift = simd_float3(-0.02, 0.0, 0.02) // Slight blue tint
                modifiedColor = modifiedColor * drizzleDarkening + drizzleColorShift
            }
            // No darkening during night - preserve base night sky colors
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
            // No cloud darkening during night - preserve base night sky colors
        }
        
        // Ensure colors stay within valid range
        return simd_clamp(modifiedColor, simd_float3(repeating: 0.0), simd_float3(repeating: 1.0))
    }
    
    enum SolarPhase {
        case day, sunrise, sunset, goldenHour, civilTwilight, nauticalTwilight, astronomicalTwilight, night
    }
    
    /// Calculate sky color using atmospheric scattering model
    private func calculateSkyColor(
        viewDirection: simd_float3,
        sunDirection: simd_float3,
        sunElevation: Float
    ) -> simd_float3 {
        
        // Handle night and twilight periods with enhanced colors
        if sunElevation < -0.314 { // Below -18 degrees (astronomical twilight)
            return calculateNightSkyColor(viewDirection: viewDirection, sunElevation: sunElevation)
        } else if sunElevation < 0 { // Twilight period
            return calculateTwilightSkyColor(
                viewDirection: viewDirection,
                sunDirection: sunDirection,
                sunElevation: sunElevation
            )
        }
        
        // Calculate optical depth through atmosphere
        let (rayleighOpticalDepth, mieOpticalDepth) = calculateOpticalDepth(direction: viewDirection)
        
        // Calculate scattering phase functions
        let cosTheta = dot(viewDirection, sunDirection)
        let rayleighPhase = calculateRayleighPhase(cosTheta: cosTheta)
        let miePhase = calculateMiePhase(cosTheta: cosTheta, g: atmosphereParams.mieDirectionalG)
        
        // Calculate sun intensity based on elevation
        let sunIntensity = calculateSunIntensity(elevation: sunElevation)
        
        // Calculate Rayleigh scattering
        let rayleighScattering = Self.rayleighCoefficients * rayleighPhase * 
                                exp(-rayleighOpticalDepth * Self.rayleighCoefficients) *
                                sunIntensity
        
        // Calculate Mie scattering  
        let mieScattering = simd_float3(repeating: Self.mieCoefficient * miePhase * 
                                       exp(-mieOpticalDepth * Self.mieCoefficient) *
                                       sunIntensity)
        
        // Combine scattering and apply tone mapping
        let totalScattering = rayleighScattering + mieScattering * atmosphereParams.mieCoefficient
        return toneMap(totalScattering)
    }
    
    /// Calculate enhanced night sky colors with subtle blue tones
    private func calculateNightSkyColor(viewDirection: simd_float3, sunElevation: Float) -> simd_float3 {
        // Base night sky color - darkened for better cloud contrast
        let baseNightColor = simd_float3(0.04, 0.07, 0.15) // Darker blue for better cloud contrast
        
        // Add subtle zenith brightening (residual atmospheric glow)
        let zenithEffect = max(0, viewDirection.y) * 0.05
        let zenithColor = simd_float3(0.08, 0.12, 0.22) * zenithEffect
        
        // Add subtle horizon glow from city lights/atmospheric effects
        let horizonHeight = 1.0 - abs(viewDirection.y)
        let horizonGlow = simd_float3(0.12, 0.08, 0.06) * horizonHeight * 0.4
        
        // Combine effects
        return baseNightColor + zenithColor + horizonGlow
    }
    
    /// Calculate twilight sky colors with enhanced atmospheric scattering
    private func calculateTwilightSkyColor(
        viewDirection: simd_float3,
        sunDirection: simd_float3,
        sunElevation: Float
    ) -> simd_float3 {
        // Twilight intensity based on sun elevation
        let twilightIntensity = exp(sunElevation * 3.0) // Exponential falloff
        
        // Enhanced atmospheric scattering for twilight
        let (rayleighOpticalDepth, mieOpticalDepth) = calculateOpticalDepth(direction: viewDirection)
        
        // Twilight-specific scattering coefficients (enhanced blue and red)
        let twilightRayleighCoeff = Self.rayleighCoefficients * simd_float3(1.5, 1.2, 2.0)
        let twilightMieCoeff = Self.mieCoefficient * 1.8
        
        let cosTheta = dot(viewDirection, sunDirection)
        let rayleighPhase = calculateRayleighPhase(cosTheta: cosTheta)
        let miePhase = calculateMiePhase(cosTheta: cosTheta, g: 0.9) // More forward scattering
        
        // Enhanced scattering for twilight
        let rayleighScattering = twilightRayleighCoeff * rayleighPhase * 
                                exp(-rayleighOpticalDepth * twilightRayleighCoeff * 0.7) *
                                twilightIntensity
        
        let mieScattering = simd_float3(repeating: twilightMieCoeff * miePhase * 
                                       exp(-mieOpticalDepth * twilightMieCoeff * 0.8) *
                                       twilightIntensity)
        
        // Add twilight-specific color enhancement
        let twilightEnhancement = calculateTwilightColorEnhancement(
            viewDirection: viewDirection,
            sunDirection: sunDirection,
            sunElevation: sunElevation
        )
        
        let totalScattering = rayleighScattering + mieScattering * 0.6 + twilightEnhancement
        
        // Blend with night sky for smooth transition
        let nightColor = calculateNightSkyColor(viewDirection: viewDirection, sunElevation: sunElevation)
        let blendFactor = max(0, min(1, (sunElevation + 0.314) / 0.314)) // Blend factor 0-1
        
        return simd_mix(nightColor, toneMap(totalScattering), simd_float3(repeating: blendFactor))
    }
    
    /// Calculate twilight-specific color enhancements
    private func calculateTwilightColorEnhancement(
        viewDirection: simd_float3,
        sunDirection: simd_float3,
        sunElevation: Float
    ) -> simd_float3 {
        let cosTheta = dot(viewDirection, sunDirection)
        
        // Enhanced orange/red colors in the anti-solar direction during twilight
        let antiSolarEffect = max(0, -cosTheta) // Stronger when looking away from sun
        let orangeEnhancement = simd_float3(0.8, 0.4, 0.1) * antiSolarEffect * abs(sunElevation) * 2.0
        
        // Purple belt effect (earth's shadow)
        let shadowBeltHeight = 1.0 - abs(viewDirection.y - 0.1) // Around 10° above horizon
        let purpleEnhancement = simd_float3(0.4, 0.2, 0.6) * shadowBeltHeight * abs(sunElevation) * 1.5
        
        // Venus belt (pink anti-twilight arch)
        let venusBeltHeight = 1.0 - abs(viewDirection.y + 0.05) // Around 5° below horizon
        let pinkEnhancement = simd_float3(0.6, 0.3, 0.4) * venusBeltHeight * antiSolarEffect * abs(sunElevation)
        
        return (orangeEnhancement + purpleEnhancement + pinkEnhancement) * 0.3
    }
    
    /// Calculate optical depth for Rayleigh and Mie scattering
    private func calculateOpticalDepth(direction: simd_float3) -> (rayleigh: Float, mie: Float) {
        // Simplified atmospheric model - assumes exponential density falloff
        let viewElevation = asin(direction.y)
        let atmosphereThickness = Self.atmosphereHeight / cos(max(0, -viewElevation))
        
        let rayleighDepth = atmosphereThickness / Self.rayleighScaleHeight
        let mieDepth = atmosphereThickness / Self.mieScaleHeight
        
        return (rayleighDepth, mieDepth)
    }
    
    /// Rayleigh phase function
    private func calculateRayleighPhase(cosTheta: Float) -> Float {
        return 3.0 / (16.0 * Float.pi) * (1.0 + cosTheta * cosTheta)
    }
    
    /// Mie phase function (Henyey-Greenstein)
    private func calculateMiePhase(cosTheta: Float, g: Float) -> Float {
        let g2 = g * g
        let denom = pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5)
        return (1.0 - g2) / (4.0 * Float.pi * denom)
    }
    
    /// Calculate sun intensity based on elevation (atmospheric absorption)
    private func calculateSunIntensity(elevation: Float) -> Float {
        if elevation <= 0 {
            // Sun is below horizon - calculate twilight scattering
            let belowHorizonAngle = -elevation
            return max(0.01, atmosphereParams.sunIntensity * exp(-belowHorizonAngle * 3.0) * 0.3)
        } else {
            // Sun is above horizon - ensure minimum intensity for visible sky
            let airMass = 1.0 / sin(max(elevation, 0.017)) // Avoid division by zero
            let absorption = exp(-airMass * 0.02) // Reduced absorption for brighter sky
            return max(0.1, atmosphereParams.sunIntensity * absorption)
        }
    }
    
    /// Simple tone mapping to convert linear to display colors
    private func toneMap(_ linearColor: simd_float3) -> simd_float3 {
        // ACES tone mapping approximation
        let a: Float = 2.51
        let b: Float = 0.03
        let c: Float = 2.43
        let d: Float = 0.59
        let e: Float = 0.14
        
        let numerator = linearColor * a + simd_float3(repeating: b)
        let denominator = linearColor * c + simd_float3(repeating: d + e)
        let mapped = numerator / denominator
        
        return simd_clamp(mapped, simd_float3(repeating: 0), simd_float3(repeating: 1))
    }
    
    // MARK: - Weather Integration
    
    /// Update atmospheric parameters based on weather conditions
    private func updateAtmosphereParams(from conditions: AtmosphericConditions) {
        // Adjust turbidity based on humidity and particles
        atmosphereParams.turbidity = 2.0 + conditions.humidity * 0.05 + conditions.particleDensity * 3.0
        
        // Adjust Mie scattering based on moisture and precipitation
        atmosphereParams.mieCoefficient = 0.005 + conditions.moisture * 0.02 + conditions.precipitationIntensity * 0.01
        
        // Adjust directional component based on particle size distribution
        atmosphereParams.mieDirectionalG = 0.8 - conditions.precipitationIntensity * 0.2
    }
}

// MARK: - Supporting Types

/// Atmospheric conditions derived from weather data
struct AtmosphericConditions {
    /// Relative humidity (0.0 to 1.0)
    let humidity: Float
    
    /// Moisture content in atmosphere (0.0 to 1.0)
    let moisture: Float
    
    /// Particle density from pollution/dust (0.0 to 1.0)
    let particleDensity: Float
    
    /// Precipitation intensity (0.0 to 1.0)
    let precipitationIntensity: Float
    
    /// Cloud cover fraction (0.0 to 1.0)
    let cloudCover: Float
    
    /// Atmospheric pressure (normalized 0.8 to 1.2)
    let pressure: Float
}
