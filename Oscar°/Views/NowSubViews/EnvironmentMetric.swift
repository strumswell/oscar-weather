//
//  EnvironmentMetric.swift
//  Oscar°
//

import SwiftUI
import UIKit

struct EnvironmentMetric: Identifiable {
    let id: String
    let label: String
    let subscriptLabel: String?
    let rawValue: Double
    let severityFraction: Double
    let color: Color
    let gradient: Gradient
    let gaugeMinLabel: String
    let gaugeMaxLabel: String

    var gaugeValue: Double { severityFraction }

    // EU AQI color stops (0-20 good → >100 extremely poor)
    private static let aqiColorStops: [(location: Double, color: Color)] = [
        (0.0, Color(red: 79/255,  green: 240/255, blue: 230/255)), // #4ff0e6 good
        (0.2, Color(red: 81/255,  green: 204/255, blue: 170/255)), // #51ccaa fair
        (0.4, Color(red: 240/255, green: 230/255, blue: 65/255)),  // #f0e641 moderate
        (0.6, Color(red: 255/255, green: 81/255,  blue: 80/255)),  // #ff5150 poor
        (0.8, Color(red: 150/255, green: 1/255,   blue: 50/255)),  // #960132 very poor
        (1.0, Color(red: 125/255, green: 33/255,  blue: 129/255)), // #7d2181 extremely poor
    ]

    // Pollen tier colors (none → very high, 5 equal steps)
    private static let pollenColorStops: [(location: Double, color: Color)] = [
        (0.0,  .green),
        (0.25, .yellow),
        (0.5,  .orange),
        (0.75, .red),
        (1.0,  .purple),
    ]

    // UV index colors per integer value (index 0–13, index 14 = >13)
    private static let uvColors: [Color] = [
        Color(red: 78/255,  green: 180/255, blue:   0),       // 0  #4eb400
        Color(red: 78/255,  green: 180/255, blue:   0),       // 1  #4eb400
        Color(red: 159/255, green: 206/255, blue:   1/255),   // 2  #9fce01
        Color(red: 247/255, green: 228/255, blue:   0),       // 3  #f7e400
        Color(red: 248/255, green: 182/255, blue:   0),       // 4  #f8b600
        Color(red: 248/255, green: 135/255, blue:   0),       // 5  #f88700
        Color(red: 248/255, green:  89/255, blue:   0),       // 6  #f85900
        Color(red: 232/255, green:  44/255, blue:  13/255),   // 7  #e82c0d
        Color(red: 216/255, green:   1/255, blue:  29/255),   // 8  #d8011d
        Color(red: 255/255, green:   0,     blue: 154/255),   // 9  #ff009a
        Color(red: 181/255, green:  76/255, blue: 255/255),   // 10 #b54cff
        Color(red: 153/255, green: 140/255, blue: 255/255),   // 11 #998cff
        Color(red: 212/255, green: 140/255, blue: 189/255),   // 12 #d48cbd
        Color(red: 234/255, green: 168/255, blue: 211/255),   // 13 #eaa8d3
        Color(red: 244/255, green: 200/255, blue: 229/255),   // >13 #f4c8e5
    ]

    static let aqiGradient = Gradient(stops: aqiColorStops.map { .init(color: $0.color, location: $0.location) })
    static let pollenGradient = Gradient(stops: pollenColorStops.map { .init(color: $0.color, location: $0.location) })
    static let uvGradient: Gradient = {
        let last = Double(uvColors.count - 1)
        return Gradient(stops: uvColors.enumerated().map { .init(color: $1, location: Double($0) / last) })
    }()

    static func forAQI(id: String, label: String, subscript_: String? = nil, value: Double?) -> EnvironmentMetric {
        let v = value ?? 0
        let fraction = min(v / 100.0, 1.0)
        return EnvironmentMetric(
            id: id, label: label, subscriptLabel: subscript_,
            rawValue: v, severityFraction: fraction,
            color: colorFromStops(aqiColorStops, at: fraction),
            gradient: aqiGradient,
            gaugeMinLabel: "0", gaugeMaxLabel: "100"
        )
    }

    static func forUV(value: Double?) -> EnvironmentMetric {
        let v = value ?? 0
        let idx = min(Int(v), uvColors.count - 1)
        let fraction = min(v / Double(uvColors.count - 1), 1.0)
        return EnvironmentMetric(
            id: "uv", label: "UV", subscriptLabel: nil,
            rawValue: v, severityFraction: fraction,
            color: uvColors[idx],
            gradient: uvGradient,
            gaugeMinLabel: "0", gaugeMaxLabel: "13"
        )
    }

    static func forPollen(type: PollenType, label: String, value: Double?) -> EnvironmentMetric? {
        guard let v = value else { return nil }
        let fraction = type.tier(for: v).severityFraction
        return EnvironmentMetric(
            id: label.lowercased(), label: label, subscriptLabel: nil,
            rawValue: v, severityFraction: fraction,
            color: colorFromStops(pollenColorStops, at: fraction),
            gradient: pollenGradient,
            gaugeMinLabel: "0", gaugeMaxLabel: "\(type.displayMax)"
        )
    }
}

func currentEnvironmentHourIndex(
    time: [Double],
    now: Date = .now,
    calendar: Calendar = .current
) -> Int? {
    guard !time.isEmpty else { return nil }

    let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
    let currentHourTimestamp = currentHour.timeIntervalSince1970

    if let exactIndex = time.firstIndex(where: { abs($0 - currentHourTimestamp) < 1 }) {
        return exactIndex
    }

    if let latestAvailableIndex = time.lastIndex(where: { $0 <= currentHourTimestamp }) {
        return latestAvailableIndex
    }

    return time.enumerated().min {
        abs($0.element - currentHourTimestamp) < abs($1.element - currentHourTimestamp)
    }?.offset
}

func environmentValue<T>(
    from values: [T]?,
    time: [Double],
    now: Date = .now,
    calendar: Calendar = .current
) -> T? {
    guard let values,
          let index = currentEnvironmentHourIndex(time: time, now: now, calendar: calendar),
          index < values.count else {
        return nil
    }

    return values[index]
}

private func colorFromStops(_ stops: [(location: Double, color: Color)], at fraction: Double) -> Color {
    for i in 0..<stops.count - 1 {
        let (t0, c0) = (stops[i].location, stops[i].color)
        let (t1, c1) = (stops[i + 1].location, stops[i + 1].color)
        if fraction <= t1 {
            let t = (fraction - t0) / (t1 - t0)
            return interpolate(c0, c1, t: t)
        }
    }
    return stops.last!.color
}

private func interpolate(_ a: Color, _ b: Color, t: Double) -> Color {
    let clamped = max(0, min(1, t))
    return Color(
        red: lerp(a.components.red, b.components.red, t: clamped),
        green: lerp(a.components.green, b.components.green, t: clamped),
        blue: lerp(a.components.blue, b.components.blue, t: clamped)
    )
}

private func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
    a + (b - a) * t
}

private extension Color {
    var components: (red: Double, green: Double, blue: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: nil)
        return (Double(r), Double(g), Double(b))
    }
}
