//
//  ClimateStripeColor.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.07.26.
//
import SwiftUI

enum ClimateStripeColor {
    struct Stop {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(red: red, green: green, blue: blue)
        }

        func interpolated(to other: Stop, fraction: Double) -> Stop {
            let fraction = min(max(fraction, 0), 1)
            return Stop(
                red: red + (other.red - red) * fraction,
                green: green + (other.green - green) * fraction,
                blue: blue + (other.blue - blue) * fraction)
        }
    }

    static let reds: [Stop] = [
        hex(0xFEE0D2), hex(0xFCBBA1), hex(0xFC9272), hex(0xFB6A4A),
        hex(0xEF3B2C), hex(0xCB181D), hex(0xA50F15), hex(0x67000D),
    ]
    static let blues: [Stop] = [
        hex(0xDEEBF7), hex(0xC6DBEF), hex(0x9ECAE1), hex(0x6BAED6),
        hex(0x4292C6), hex(0x2171B5), hex(0x08519C), hex(0x08306B),
    ]
    static let fullScaleSigma = 3.0

    static func color(anomaly: Double, sigma: Double) -> Color {
        let referenceSigma = max(sigma, 0.001)
        let rampMagnitude = min(abs(anomaly) / referenceSigma / fullScaleSigma, 1)
        let stops = anomaly >= 0 ? reds : blues
        let position = rampMagnitude * Double(stops.count - 1)
        let lowerIndex = min(Int(position.rounded(.down)), stops.count - 1)
        let upperIndex = min(lowerIndex + 1, stops.count - 1)
        if lowerIndex == upperIndex { return stops[lowerIndex].color }
        return stops[lowerIndex]
            .interpolated(to: stops[upperIndex], fraction: position - Double(lowerIndex))
            .color
    }

    static var legendGradient: [Color] {
        (Array(blues.reversed()) + reds).map(\.color)
    }

    private static func hex(_ value: UInt32) -> Stop {
        Stop(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
