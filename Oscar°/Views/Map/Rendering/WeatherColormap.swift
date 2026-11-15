//
//  WeatherColormap.swift
//  Oscar°
//
//  Client-side colormap definitions for the map legends (kept in sync with the
//  server palettes), plus the gradient line and vertical legend views.
//

import SwiftUI

// MARK: - Colormap

enum WeatherColormap {
    case radar, temperature, wind, pressure

    var colors: [Color] {
        switch self {
        case .radar:
            return ServerColormapStops.radar.map { Color(hex: $0.hex) }
        case .temperature:
            return ServerColormapStops.temperature.map { Color(hex: $0) }
        case .wind:
            return ServerColormapStops.wind.map { Color(hex: $0) }
        case .pressure:
            return ServerColormapStops.pressure.map { Color(hex: $0.hex) }
        }
    }

    func verticalLabels(_ units: Units) -> [(Double, Text)] {
        switch self {
        case .radar:
            return [
                (0.00, Text("Niesel")),
                (0.25, Text("Leicht")),
                (0.50, Text("Mäßig")),
                (0.75, Text("Stark")),
                (1.00, Text("Extrem")),
            ]
        case .temperature:
            return (0...9).map { step in
                let value = units.temperature.rounded(Double(step * 10 - 40))
                let sign = value > 0 ? "+" : ""
                return (Double(step) / 9, Text(verbatim: "\(sign)\(value) \(units.temperature.symbol)"))
            }
        case .wind:
            return (0...4).map { step in
                let prefix = step == 4 ? "≥" : ""
                return (Double(step) / 4, Text(verbatim: "\(prefix)\(units.windNumber(Double(step) * 2 * 3.6)) \(units.wind.symbol)"))
            }
        case .pressure:
            return [(0.000, 950), (0.182, 970), (0.364, 990), (0.545, 1010), (0.727, 1030), (1.000, 1060)]
                .map { ($0.0, Text(verbatim: units.pressureNumber($0.1))) }
        }
    }

    var gradientStops: [Gradient.Stop] {
        if case .pressure = self {
            let stops = ServerColormapStops.pressure
            let low = stops.first!.hpa, span = stops.last!.hpa - low
            return stops.map {
                .init(color: Color(hex: $0.hex), location: ($0.hpa - low) / span)
            }
        }
        let n = colors.count
        guard n > 1 else { return colors.map { .init(color: $0, location: 0) } }
        return colors.enumerated().map { i, c in
            .init(color: c, location: Double(i) / Double(n - 1))
        }
    }
}

extension WeatherTileLayer {
    var colormap: WeatherColormap {
        switch self {
        case .iconPrecip,   .ecmwfPrecip:   return .radar
        case .iconTemp,     .ecmwfTemp:     return .temperature
        case .iconWind,     .ecmwfWind:     return .wind
        case .iconPressure, .ecmwfPressure: return .pressure
        }
    }
}

// MARK: - Storm-cell legend (shown while the Regenzellen layer is on)

struct StormCellLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Regenzellen")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(ServerColormapStops.stormCellSteps.enumerated(), id: \.offset) { _, step in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hex: step.hex))
                        .frame(width: 8, height: 8)
                        .overlay { Circle().stroke(.white.opacity(0.8), lineWidth: 1) }
                    Text(step.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Vertical legend (beside map badge)

struct ColormapVerticalLegend: View {
    let colormap: WeatherColormap
    private let barWidth: CGFloat = 10
    private var labels: [(Double, Text)] { colormap.verticalLabels(SettingService.shared.units) }
    private var barHeight: CGFloat { CGFloat(labels.count) * 20 }

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            LinearGradient(stops: colormap.gradientStops, startPoint: .bottom, endPoint: .top)
                .frame(width: barWidth, height: barHeight)
                .clipShape(RoundedRectangle(cornerRadius: barWidth / 2))

            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: 52, height: barHeight)
                ForEach(labels.enumerated(), id: \.offset) { _, entry in
                    let inset = barWidth / 2
                    entry.1
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .offset(y: inset + (barHeight - barWidth) * (1 - entry.0) - 6)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(in: RoundedRectangle(cornerRadius: 12))
    }
}
