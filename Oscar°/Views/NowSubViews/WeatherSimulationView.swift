//
//  WeatherSimulationView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 02.01.24.
//

import SwiftUI
import CoreLocation

struct WeatherSimulationView: View {
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location
    
    private let atmosphericAdapter = WeatherAtmosphericAdapter()
    
    var body: some View {
        ZStack {
            if !weather.isLoading && weather.forecast.hourly != nil {
                StarsView()
                if getCloudDensity() != Cloud.Thickness.thick {
                    SunView(progress: weather.time)
                }
                CloudsView(
                    thickness: getCloudDensity(),
                    topTint: getAtmosphericCloudTopTint(),
                    bottomTint: getAtmosphericCloudBottomTint()
                )
                if shouldDisplayStorm {
                    StormView(type: getStormType(), direction: .degrees(30), strength: getStormIntensity())
                }
            }
            if weather.debug {
                VStack {
                    Text(weather.isLoading.description)
                    Text(String(reflecting: weather.forecast.hourly == nil))
                }
            }
        }
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(atmosphericBackgroundGradient)
    }
}

#Preview {
    WeatherSimulationView()
}

extension WeatherSimulationView {
    /// Atmospheric physics-based background gradient
    var atmosphericBackgroundGradient: LinearGradient {
        // Only use atmospheric rendering if location is available
        guard location.coordinates.latitude != 0 && location.coordinates.longitude != 0 else {
            if weather.debug {
                print("🌍 WeatherSimulationView: Using legacy gradient - Location not available: \(location.coordinates)")
            }
            return legacyBackgroundGradient
        }
        
        if weather.debug {
            print("🌍 WeatherSimulationView: Using atmospheric renderer at \(location.coordinates)")
        }
        
        return atmosphericAdapter.generateAtmosphericSkyGradient(
            from: weather,
            at: location.coordinates
        )
    }
    
    /// Legacy gradient system as fallback
    var legacyBackgroundGradient: LinearGradient {
        LinearGradient(colors: [
            getBackgroundTopStops().interpolated(amount: weather.time),
            getBackgroundBottomStops().interpolated(amount: weather.time)
        ], startPoint: .top, endPoint: .bottom)
    }
    
    /// Get atmospheric color for cloud top tinting
    func getAtmosphericCloudTopTint() -> Color {
        guard location.coordinates.latitude != 0 && location.coordinates.longitude != 0 else {
            // Fallback to legacy system if no location
            return getCloudTopStops().interpolated(amount: weather.time)
        }
        
        return atmosphericAdapter.getAtmosphericCloudColor(
            from: weather,
            at: location.coordinates,
            isTop: true
        )
    }
    
    /// Get atmospheric color for cloud bottom tinting
    func getAtmosphericCloudBottomTint() -> Color {
        guard location.coordinates.latitude != 0 && location.coordinates.longitude != 0 else {
            // Fallback to legacy system if no location
            return getCloudBottomStops().interpolated(amount: weather.time)
        }
        
        return atmosphericAdapter.getAtmosphericCloudColor(
            from: weather,
            at: location.coordinates,
            isTop: false
        )
    }

    var shouldDisplayStorm: Bool {
        (weather.forecast.current?.weathercode ?? 0 >= 51 && weather.forecast.current?.precipitation ?? 0 > 0) || weather.radar.isRaining()
    }
    
    func getBackgroundTopStops() -> [Gradient.Stop] {
        if (weather.forecast.hourly == nil) {
            return [
                .init(color: .midnightStart, location: 0),
                .init(color: .midnightStart, location: 0.25),
                .init(color: .sunriseStart, location: 0.33),
                .init(color: .sunnyDayStart, location: 0.38),
                .init(color: .sunnyDayStart, location: 0.65),
                .init(color: .sunsetStart, location: 0.69),
                .init(color: .midnightStart, location: 0.8),
                .init(color: .midnightStart, location: 1)
            ]
        }
        
        let dayLength = 86400.0
        let dayBegin = weather.forecast.hourly?.time.first ?? 0
        let sunrise = weather.forecast.daily?.sunrise?.first ?? 0
        let sunset = weather.forecast.daily?.sunset?.first ?? 0
        
        if (weather.forecast.current?.weathercode ?? 0 >= 51 && weather.forecast.current?.precipitation ?? 0 > 0) || weather.radar.isRaining() {
            return [
                .init(color: .midnightStart, location: 0),
                .init(color: .midnightStart, location: (sunrise - dayBegin)/dayLength - 0.08),
                .init(color: .rainyStart, location: (sunrise - dayBegin)/dayLength),
                .init(color: .rainyStart, location: (sunrise - dayBegin)/dayLength + 0.05),
                .init(color: .rainyStart, location: (sunset - dayBegin)/dayLength - 0.08),
                .init(color: .rainyStart, location: (sunset - dayBegin)/dayLength),
                .init(color: .midnightStart, location: (sunset - dayBegin)/dayLength + 0.04),
                .init(color: .midnightStart, location: 1)
            ]
        }
        
        return [
            .init(color: .midnightStart, location: 0),
            .init(color: .midnightStart, location: (sunrise - dayBegin)/dayLength - 0.08),
            .init(color: .sunriseStart, location: (sunrise - dayBegin)/dayLength),
            .init(color: .sunnyDayStart, location: (sunrise - dayBegin)/dayLength + 0.05),
            .init(color: .sunnyDayStart, location: (sunset - dayBegin)/dayLength - 0.08),
            .init(color: .sunsetStart, location: (sunset - dayBegin)/dayLength),
            .init(color: .midnightStart, location: (sunset - dayBegin)/dayLength + 0.04),
            .init(color: .midnightStart, location: 1)
        ]
    }
    
    func getBackgroundBottomStops() -> [Gradient.Stop] {
        if (weather.forecast.hourly == nil) {
            return [
                .init(color: .midnightEnd, location: 0),
                .init(color: .midnightEnd, location: 0.25),
                .init(color: .sunriseEnd, location: 0.33),
                .init(color: .sunnyDayEnd, location: 0.38),
                .init(color: .sunnyDayEnd, location: 0.65),
                .init(color: .sunsetEnd, location: 0.69),
                .init(color: .midnightEnd, location: 0.8),
                .init(color: .midnightEnd, location: 1)
            ]
        }
        
        let dayLength = 86400.0
        let dayBegin = weather.forecast.hourly?.time.first ?? 0
        let sunrise = weather.forecast.daily?.sunrise?.first ?? 0
        let sunset = weather.forecast.daily?.sunset?.first ?? 0
        
        if (weather.forecast.current?.weathercode ?? 0 >= 51 && weather.forecast.current?.precipitation ?? 0 > 0) || weather.radar.isRaining() {
            return [
                .init(color: .midnightEnd, location: 0),
                .init(color: .midnightEnd, location: (sunrise - dayBegin)/dayLength - 0.08),
                .init(color: .rainyEnd, location: (sunrise - dayBegin)/dayLength),
                .init(color: .rainyEnd, location: (sunrise - dayBegin)/dayLength + 0.05),
                .init(color: .rainyEnd, location: (sunset - dayBegin)/dayLength - 0.08),
                .init(color: .rainyEnd, location: (sunset - dayBegin)/dayLength),
                .init(color: .midnightEnd, location: (sunset - dayBegin)/dayLength + 0.015),
                .init(color: .midnightEnd, location: 1)
            ]
        }
        
        return [
            .init(color: .midnightEnd, location: 0),
            .init(color: .midnightEnd, location: (sunrise - dayBegin)/dayLength - 0.08),
            .init(color: .sunriseEnd, location: (sunrise - dayBegin)/dayLength),
            .init(color: .sunnyDayEnd, location: (sunrise - dayBegin)/dayLength + 0.05),
            .init(color: .sunnyDayEnd, location: (sunset - dayBegin)/dayLength - 0.08),
            .init(color: .sunsetEnd, location: (sunset - dayBegin)/dayLength),
            .init(color: .midnightEnd, location: (sunset - dayBegin)/dayLength + 0.015),
            .init(color: .midnightEnd, location: 1)
        ]
    }
    
    func getCloudTopStops() -> [Gradient.Stop] {
        if (weather.forecast.hourly == nil) {
            return [
                .init(color: .darkCloudStart, location: 0),
                .init(color: .darkCloudStart, location: 0.25),
                .init(color: .sunriseCloudStart, location: 0.33),
                .init(color: .lightCloudStart, location: 0.38),
                .init(color: .lightCloudStart, location: 0.7),
                .init(color: .sunsetCloudStart, location: 0.78),
                .init(color: .darkCloudStart, location: 0.82),
                .init(color: .darkCloudStart, location: 1)
            ]
        }
        
        let dayLength = 86400.0
        let dayBegin = weather.forecast.hourly?.time.first ?? 0
        let sunrise = weather.forecast.daily?.sunrise?.first ?? 0
        let sunset = weather.forecast.daily?.sunset?.first ?? 0
        
        if (weather.forecast.current?.weathercode ?? 0 >= 51 && weather.forecast.current?.precipitation ?? 0 > 0) || weather.radar.isRaining() {
            return [
                .init(color: .darkCloudStart, location: 0),
                .init(color: .darkCloudStart, location: (sunrise - dayBegin)/dayLength - 0.08),
                .init(color: .rainCloudStart, location: (sunrise - dayBegin)/dayLength),
                .init(color: .rainCloudStart, location: (sunrise - dayBegin)/dayLength + 0.05),
                .init(color: .rainCloudStart, location: (sunset - dayBegin)/dayLength - 0.08),
                .init(color: .rainCloudStart, location: (sunset - dayBegin)/dayLength),
                .init(color: .darkCloudStart, location: (sunset - dayBegin)/dayLength + 0.015),
                .init(color: .darkCloudStart, location: 1)
            ]
        }
        
        return [
            .init(color: .darkCloudStart, location: 0),
            .init(color: .darkCloudStart, location: (sunrise - dayBegin)/dayLength - 0.08),
            .init(color: .sunriseCloudStart, location: (sunrise - dayBegin)/dayLength),
            .init(color: .lightCloudStart, location: (sunrise - dayBegin)/dayLength + 0.05),
            .init(color: .lightCloudStart, location: (sunset - dayBegin)/dayLength - 0.08),
            .init(color: .sunsetCloudStart, location: (sunset - dayBegin)/dayLength),
            .init(color: .darkCloudStart, location: (sunset - dayBegin)/dayLength + 0.015),
            .init(color: .darkCloudStart, location: 1)
        ]
    }
    
    func getCloudBottomStops() -> [Gradient.Stop] {
        if (weather.forecast.hourly == nil) {
            return [
                .init(color: .darkCloudEnd, location: 0),
                .init(color: .darkCloudEnd, location: 0.25),
                .init(color: .sunriseCloudEnd, location: 0.33),
                .init(color: .lightCloudEnd, location: 0.38),
                .init(color: .lightCloudEnd, location: 0.7),
                .init(color: .sunsetCloudEnd, location: 0.78),
                .init(color: .darkCloudEnd, location: 0.92),
                .init(color: .darkCloudEnd, location: 1)
            ]
        }
        
        let dayLength = 86400.0
        let dayBegin = weather.forecast.hourly?.time.first ?? 0
        let sunrise = weather.forecast.daily?.sunrise?.first ?? 0
        let sunset = weather.forecast.daily?.sunset?.first ?? 0
        
        if (weather.forecast.current?.weathercode ?? 0 >= 51 && weather.forecast.current?.precipitation ?? 0 > 0) || weather.radar.isRaining() {
            return [
                .init(color: .darkCloudEnd, location: 0),
                .init(color: .darkCloudEnd, location: (sunrise - dayBegin)/dayLength - 0.08),
                .init(color: .rainCloudEnd, location: (sunrise - dayBegin)/dayLength),
                .init(color: .rainCloudEnd, location: (sunrise - dayBegin)/dayLength + 0.05),
                .init(color: .rainCloudEnd, location: (sunset - dayBegin)/dayLength - 0.08),
                .init(color: .rainCloudEnd, location: (sunset - dayBegin)/dayLength),
                .init(color: .darkCloudEnd, location: (sunset - dayBegin)/dayLength + 0.04),
                .init(color: .darkCloudEnd, location: 1)
            ]
        }
        
        return [
            .init(color: .darkCloudEnd, location: 0),
            .init(color: .darkCloudEnd, location: (sunrise - dayBegin)/dayLength - 0.08),
            .init(color: .sunriseCloudEnd, location: (sunrise - dayBegin)/dayLength),
            .init(color: .lightCloudEnd, location: (sunrise - dayBegin)/dayLength + 0.05),
            .init(color: .lightCloudEnd, location: (sunset - dayBegin)/dayLength - 0.08),
            .init(color: .sunsetCloudEnd, location: (sunset - dayBegin)/dayLength),
            .init(color: .darkCloudEnd, location: (sunset - dayBegin)/dayLength + 0.04),
            .init(color: .darkCloudEnd, location: 1)
        ]
    }
    
    public func getCloudDensity() -> Cloud.Thickness {
        switch weather.forecast.current?.weathercode {
        case 0:
            return Cloud.Thickness.none
        case 1:
            return Cloud.Thickness.light
        case 2:
            return Cloud.Thickness.regular
        case 3:
            return Cloud.Thickness.thick
        default:
            return Cloud.Thickness.thick
        }
    }
    
    public func getStormType() -> Storm.Contents {
        switch weather.forecast.current?.weathercode {
        case 51, 53, 55, 61, 63, 65, 66, 67, 95, 96, 99:
            return Storm.Contents.rain
        case 71, 73, 75, 77, 85, 86:
            return Storm.Contents.snow
        default:
            return Storm.Contents.none
        }
    }
    
    public func getStormIntensity() -> Int {
        switch weather.forecast.current?.weathercode {
        case 51, 53, 55, 56, 57:
            return 30
        case 61:
            return 40
        case 63:
            return 50
        case 65, 67:
            return 70
        case 71:
            return 90
        case 73:
            return 150
        case 75:
            return 300
        case 77:
            return 50
        case 80, 85, 95, 99:
            return 20
        case 81:
            return 80
        case 82, 86:
            return 90
        default:
            return 40
        }
    }
}
