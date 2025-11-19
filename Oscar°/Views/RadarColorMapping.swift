//
//  RadarColorMapping.swift
//  Oscar°
//
//  Color mapping for DWD radar transformation
//  Maps new yellow-red scheme to old blue-purple scheme
//

import UIKit

struct RadarColorMapping {
    // Old DWD color scheme (approximate RGB values from the legend)
    // Based on rainfall intensity ranges
    static let oldColorScheme: [(intensity: ClosedRange<Double>, color: (r: UInt8, g: UInt8, b: UInt8))] = [
        (0.0...0.1,   (r: 255, g: 255, b: 255)),  // White/transparent
        (0.1...1.0,   (r: 245, g: 250, b: 255)),  // Very pale blue-white
        (1.0...2.0,   (r: 230, g: 245, b: 255)),  // Pale blue
        (2.0...5.0,   (r: 200, g: 235, b: 255)),  // Light blue
        (5.0...10.0,  (r: 150, g: 220, b: 255)),  // Light cyan-blue
        (10.0...15.0, (r: 100, g: 200, b: 240)),  // Cyan
        (15.0...20.0, (r: 50, g: 180, b: 230)),   // Cyan-blue
        (20.0...30.0, (r: 30, g: 140, b: 220)),   // Blue
        (30.0...50.0, (r: 20, g: 80, b: 200)),    // Dark blue
        (50.0...80.0, (r: 100, g: 50, b: 180)),   // Purple
        (80.0...100.0, (r: 180, g: 50, b: 150)),  // Magenta
        (100.0...150.0, (r: 220, g: 50, b: 80)),  // Red-magenta
        (150.0...200.0, (r: 200, g: 30, b: 30)),  // Dark red
        (200.0...1000.0, (r: 120, g: 20, b: 20)), // Very dark red/brown
    ]

    // New DWD color scheme (approximate - yellow to red)
    static let newColorScheme: [(intensity: ClosedRange<Double>, color: (r: UInt8, g: UInt8, b: UInt8))] = [
        (0.0...0.1,   (r: 255, g: 255, b: 255)),  // White/transparent
        (0.1...1.0,   (r: 255, g: 255, b: 200)),  // Very pale yellow
        (1.0...2.0,   (r: 255, g: 250, b: 150)),  // Pale yellow
        (2.0...5.0,   (r: 255, g: 240, b: 100)),  // Yellow
        (5.0...10.0,  (r: 255, g: 220, b: 80)),   // Yellow-orange
        (10.0...15.0, (r: 255, g: 180, b: 50)),   // Orange
        (15.0...20.0, (r: 255, g: 140, b: 30)),   // Dark orange
        (20.0...30.0, (r: 255, g: 100, b: 20)),   // Orange-red
        (30.0...50.0, (r: 240, g: 60, b: 20)),    // Red-orange
        (50.0...80.0, (r: 220, g: 30, b: 30)),    // Red
        (80.0...100.0, (r: 180, g: 20, b: 50)),   // Dark red
        (100.0...150.0, (r: 150, g: 20, b: 80)),  // Dark red-purple
        (150.0...200.0, (r: 120, g: 20, b: 100)), // Purple-brown
        (200.0...1000.0, (r: 80, g: 20, b: 80)),  // Dark purple-brown
    ]

    static func transformColor(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        // Skip transparent pixels
        guard a > 10 else {
            return (r: r, g: g, b: b, a: a)
        }

        let rf = CGFloat(r) / 255.0
        let gf = CGFloat(g) / 255.0
        let bf = CGFloat(b) / 255.0

        // Detect color characteristics
        let brightness = (rf + gf + bf) / 3.0
        let warmness = rf / (bf + 0.01)  // High for yellow/red, low for blue

        var newR: CGFloat = 0
        var newG: CGFloat = 0
        var newB: CGFloat = 0

        // Map based on the new color scheme
        // Very light colors (0.1-1 mm): pale yellow -> pale blue
        if brightness > 0.9 && warmness > 1.0 {
            newR = 0.96
            newG = 0.98
            newB = 1.0
        }
        // Light yellow (1-5 mm): yellow/pale orange -> light blue/cyan
        else if rf > 0.85 && gf > 0.75 && bf < 0.65 {
            let yellowIntensity = (rf + gf) / 2.0 - bf
            newR = 0.78 - yellowIntensity * 0.2
            newG = 0.92 - yellowIntensity * 0.05
            newB = 1.0
        }
        // Medium yellow-orange (5-15 mm): -> cyan/light blue
        else if rf > 0.75 && gf > 0.5 && gf < 0.9 && bf < 0.4 {
            let orangeLevel = (1.0 - gf) * 2.0
            newR = 0.39 - orangeLevel * 0.2
            newG = 0.78 + orangeLevel * 0.1
            newB = 0.94
        }
        // Orange (15-30 mm): -> blue
        else if rf > 0.65 && gf > 0.3 && gf < 0.6 && bf < 0.25 {
            let intensity = (rf - gf) * 2.0
            newR = 0.12 - intensity * 0.1
            newG = 0.55 + intensity * 0.15
            newB = 0.86 + intensity * 0.05
        }
        // Red-orange to red (30-80 mm): -> dark blue to purple
        else if rf > 0.6 && gf < 0.4 && bf < 0.4 {
            let redLevel = (rf - gf) / rf
            if redLevel > 0.7 {
                // High red -> purple
                newR = 0.39 + (1.0 - redLevel) * 0.3
                newG = 0.20
                newB = 0.71 - (1.0 - redLevel) * 0.2
            } else {
                // Orange-red -> dark blue
                newR = 0.08 + redLevel * 0.1
                newG = 0.31 - redLevel * 0.2
                newB = 0.78 + redLevel * 0.08
            }
        }
        // Very dark red/purple (80+ mm): -> magenta/red
        else if rf > 0.4 && rf < 0.75 && gf < 0.3 {
            let darkness = 1.0 - brightness
            if darkness > 0.5 {
                // Very dark -> keep similar (dark red/brown)
                newR = 0.47 + darkness * 0.2
                newG = 0.12
                newB = 0.12
            } else {
                // Dark red -> magenta
                newR = 0.71
                newG = 0.20
                newB = 0.59
            }
        }
        // Extreme (100+ mm): dark purple/brown -> dark red
        else if brightness < 0.4 && rf > gf && rf > bf {
            newR = 0.78
            newG = 0.12
            newB = 0.31
        }
        // Already blue-ish (maybe already transformed or edge case)
        else if bf > rf && bf > gf {
            newR = rf
            newG = gf
            newB = bf
        }
        // Purple/magenta already present
        else if rf > 0.6 && bf > 0.5 {
            newR = rf
            newG = gf * 0.8
            newB = bf
        }
        // Default fallback: map by brightness to blue scale
        else {
            if brightness < 0.3 {
                newR = 0.08
                newG = 0.31
                newB = 0.86
            } else if brightness < 0.6 {
                newR = 0.39
                newG = 0.78
                newB = 0.94
            } else {
                newR = 0.96
                newG = 0.98
                newB = 1.0
            }
        }

        // Clamp values
        newR = max(0, min(1, newR))
        newG = max(0, min(1, newG))
        newB = max(0, min(1, newB))

        return (
            r: UInt8(newR * 255.0),
            g: UInt8(newG * 255.0),
            b: UInt8(newB * 255.0),
            a: a
        )
    }
}
