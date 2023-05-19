//
//  Color-Custom.swift
//  Weather
//
//  Created by Paul Hudson on 16/11/2021.
//

import SwiftUI

extension Color {
    static let midnightStart = Color(hue: 0.66, saturation: 0.8, brightness: 0.1)
    static let midnightEnd = Color(hue: 0.62, saturation: 0.5, brightness: 0.33)
    static let sunriseStart = Color(hue: 0.62, saturation: 0.6, brightness: 0.42)
    static let sunriseEnd = Color(hue: 0.95, saturation: 0.35, brightness: 0.66)
    static let sunnyDayStart = Color(hue: 0.6, saturation: 0.6, brightness: 0.6)
    static let sunnyDayEnd = Color(hue: 0.6, saturation: 0.4, brightness: 0.85)
    static let sunsetStart = Color.sunriseStart
    static let sunsetEnd = Color(hue: 0.05, saturation: 0.34, brightness: 0.65)

    static let darkCloudStart = Color(hue: 0.65, saturation: 0.3, brightness: 0.3)
    static let darkCloudEnd = Color(hue: 0.65, saturation: 0.3, brightness: 0.7)
    static let lightCloudStart = Color.white
    static let lightCloudEnd = Color(white: 0.75)
    static let sunriseCloudStart = Color.lightCloudStart
    static let sunriseCloudEnd = Color.sunriseEnd
    static let sunsetCloudStart = Color.lightCloudStart
    static let sunsetCloudEnd = Color.sunsetEnd
    
    static let rainCloudStart = Color(white: 0.75)
    static let rainCloudEnd = Color(white: 0.3)

    static let rainyStart = Color(hue: 0.6, saturation: 0.2, brightness: 0.35)
    static let rainyEnd = Color(hue: 0.6, saturation: 0.4, brightness: 0.35)
}
