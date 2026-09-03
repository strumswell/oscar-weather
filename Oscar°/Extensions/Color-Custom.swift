//
//  Color-Custom.swift
//  Oscar°
//
//  Created by Paul Hudson on 16/11/2021.
//

import SwiftUI

extension Color {
    init(hex: Int, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8)  & 0xff) / 255,
            blue:  Double( hex        & 0xff) / 255,
            opacity: alpha
        )
    }

    static let midnightStart = Color(hue: 0.66, saturation: 0.8, brightness: 0.1)
    static let midnightEnd = Color(hue: 0.62, saturation: 0.5, brightness: 0.33)
    static let sunriseStart = Color(hue: 0.62, saturation: 0.6, brightness: 0.42)
    static let sunnyDayStart = Color(hue: 0.6, saturation: 0.6, brightness: 0.6)
    static let sunnyDayEnd = Color(hue: 0.6, saturation: 0.4, brightness: 0.85)
}
