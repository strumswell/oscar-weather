//
//  WeatherColormap.swift
//  Oscar°
//
//  Client-side colormap definitions for the map legends (kept in sync with the
//  server palettes), plus the gradient line and vertical legend views.
//

import SwiftUI

// MARK: - Colormap
// ===========================================================================

enum WeatherColormap {
    case radar, temperature, wind

    // Colors ordered from minimum → maximum value
    var colors: [Color] {
        switch self {
        case .radar:
            return [
                Color(hex: 0x99ffff), // drizzle
                Color(hex: 0x32ffff),
                Color(hex: 0x00caca),
                Color(hex: 0x009934),
                Color(hex: 0x4cbf19),
                Color(hex: 0x98cb03),
                Color(hex: 0xcce603),
                Color(hex: 0xffff00),
                Color(hex: 0xffc400),
                Color(hex: 0xff8901),
                Color(hex: 0xff0000),
                Color(hex: 0xb40000),
                Color(hex: 0x4848ff),
                Color(hex: 0x0000c9),
                Color(hex: 0x990199),
                Color(hex: 0xfe33ff), // extreme / hail
            ]
        case .temperature:
            return [
                Color(hex: 0x3f49b3), // ≤ −40 °C
                Color(hex: 0x4263d8),
                Color(hex: 0x3f7df1),
                Color(hex: 0x3896f9),
                Color(hex: 0x2bb1ef),
                Color(hex: 0x1ec9d8),
                Color(hex: 0x20dbbf),
                Color(hex: 0x25eca5),
                Color(hex: 0xd2e92a), // 0 °C
                Color(hex: 0xe3d630),
                Color(hex: 0xf0c331),
                Color(hex: 0xf7ad2b),
                Color(hex: 0xf89525),
                Color(hex: 0xf77b1a),
                Color(hex: 0xed610e),
                Color(hex: 0xe14906),
                Color(hex: 0xd13503),
                Color(hex: 0xbe2400),
                Color(hex: 0xa91500), // ≥ +50 °C
            ]
        case .wind:
            return [
                Color(hex: 0xf7fcff), // 0–1 m/s
                Color(hex: 0xd2ddf2),
                Color(hex: 0xadbfe5),
                Color(hex: 0x9a9edc),
                Color(hex: 0x8a7fcf),
                Color(hex: 0x795eb5),
                Color(hex: 0x693e9a),
                Color(hex: 0x581d77),
                Color(hex: 0x4a0059), // ≥ 8 m/s
            ]
        }
    }

    // (fraction 0…1 from bottom/min, label text) for the vertical legend
    var verticalLabels: [(Double, LocalizedStringKey)] {
        switch self {
        case .radar:
            return [
                (0.00, "Niesel"),
                (0.25, "Leicht"),
                (0.50, "Mäßig"),
                (0.75, "Stark"),
                (1.00, "Extrem"),
            ]
        case .temperature:
            // 19 colours, 5 °C/step → fraction = index / 18
            return [
                (0.000, "−40 °C"),
                (0.111, "−30 °C"),
                (0.222, "−20 °C"),
                (0.333, "−10 °C"),
                (0.444,   "0 °C"),
                (0.556, "+10 °C"),
                (0.667, "+20 °C"),
                (0.778, "+30 °C"),
                (0.889, "+40 °C"),
                (1.000, "+50 °C"),
            ]
        case .wind:
            return [
                (0.00, "0 m/s"),
                (0.25, "2 m/s"),
                (0.50, "4 m/s"),
                (0.75, "6 m/s"),
                (1.00, "≥8 m/s"),
            ]
        }
    }

    var unit: String {
        switch self {
        case .radar:       return "mm/h"
        case .temperature: return "°C"
        case .wind:        return "m/s"
        }
    }

    // Evenly-spaced gradient stops (min at 0, max at 1)
    var gradientStops: [Gradient.Stop] {
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
        case .iconPrecip, .gfsPrecip: return .radar
        case .iconTemp,   .gfsTemp:   return .temperature
        case .iconWind,   .gfsWind:   return .wind
        }
    }
}

// MARK: - Vertical legend (beside map badge)

struct ColormapVerticalLegend: View {
    let colormap: WeatherColormap
    private let barWidth: CGFloat = 10
    private var barHeight: CGFloat { CGFloat(colormap.verticalLabels.count) * 20 }

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            // Gradient bar — low at bottom, high at top
            LinearGradient(stops: colormap.gradientStops, startPoint: .bottom, endPoint: .top)
                .frame(width: barWidth, height: barHeight)
                .clipShape(RoundedRectangle(cornerRadius: barWidth / 2))

            // Labels pinned by fraction
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: 52, height: barHeight)
                ForEach(Array(colormap.verticalLabels.enumerated()), id: \.offset) { _, entry in
                    let inset = barWidth / 2
                    Text(entry.1)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        // Shrink the label range by the corner-radius inset so top/bottom
                        // labels align with the actual start/end of the visible gradient.
                        .offset(y: inset + (barHeight - barWidth) * (1 - entry.0) - 6)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(in: RoundedRectangle(cornerRadius: 12))
    }
}
