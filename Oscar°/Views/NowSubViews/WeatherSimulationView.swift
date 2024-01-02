//
//  WeatherSimulationView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 02.01.24.
//

import SwiftUI

struct WeatherSimulationView: View {
    @Environment(Weather.self) private var weather: Weather

    var body: some View {
        ZStack {
            StarsView()
            if weather.forecast.current?.precipitation ?? 0 > 0 {
                CloudsView(
                    thickness: Cloud.Thickness.thick,
                    topTint: getCloudTopStops().interpolated(amount: weather.time),
                    bottomTint: getCloudBottomStops().interpolated(amount: weather.time)
                )
                StormView(type: Storm.Contents.rain, direction: .degrees(30), strength: 80)
            } else {
                if getCloudDensity() != Cloud.Thickness.thick {
                    SunView(progress: weather.time)
                }
                CloudsView(
                    thickness: getCloudDensity(),
                    topTint: getCloudTopStops().interpolated(amount: weather.time),
                    bottomTint: getCloudBottomStops().interpolated(amount: weather.time)
                )
            }
        }
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [
                getBackgroundTopStops().interpolated(amount: weather.time),
                getBackgroundBottomStops().interpolated(amount: weather.time)
            ], startPoint: .top, endPoint: .bottom)
        )
    }
}

#Preview {
    WeatherSimulationView()
}

extension WeatherSimulationView {
    func getBackgroundTopStops() -> [Gradient.Stop] {
        if (weather.forecast.hourly == nil) {
            return [
                .init(color: .midnightStart, location: 0),
                .init(color: .midnightStart, location: 0.25),
                .init(color: .sunriseStart, location: 0.33),
                .init(color: .sunnyDayStart, location: 0.38),
                .init(color: .sunnyDayStart, location: 0.7),
                .init(color: .sunsetStart, location: 0.78),
                .init(color: .midnightStart, location: 0.82),
                .init(color: .midnightStart, location: 1)
            ]
        }
        
        let dayLength = 86400.0
        let dayBegin = weather.forecast.hourly?.time.first ?? 0
        let sunrise = weather.forecast.daily?.sunrise?.first ?? 0
        let sunset = weather.forecast.daily?.sunset?.first ?? 0
        
        if weather.forecast.current?.precipitation ?? 0 > 0 {
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
                .init(color: .sunnyDayEnd, location: 0.7),
                .init(color: .sunsetEnd, location: 0.78),
                .init(color: .midnightEnd, location: 0.82),
                .init(color: .midnightEnd, location: 1)
            ]
        }
        
        let dayLength = 86400.0
        let dayBegin = weather.forecast.hourly?.time.first ?? 0
        let sunrise = weather.forecast.daily?.sunrise?.first ?? 0
        let sunset = weather.forecast.daily?.sunset?.first ?? 0
        
        if weather.forecast.current?.precipitation ?? 0 > 0 {
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
        
        if weather.forecast.current?.precipitation ?? 0 > 0 {
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
        
        if weather.forecast.current?.precipitation ?? 0 > 0 {
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
        case 45, 48, 51, 52, 55, 61, 63, 65, 66, 67, 71, 73, 75, 77, 85, 86, 95, 96, 99:
            return Cloud.Thickness.thick
        default:
            return Cloud.Thickness.light
        }
    }
    
    public func getStormType() -> Storm.Contents {
        switch weather.forecast.current?.weathercode {
        case 51, 52, 55, 61, 63, 65, 66, 67, 71, 73, 75, 77, 85, 86, 95, 96, 99:
            return Storm.Contents.rain
        default:
            return Storm.Contents.none
        }
    }
}
