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

/// Canonical client-side copies of oscar-server's palette stops
/// (`Sources/App/Imaging/Colormaps.swift`). The map colors value grids with the
/// palettes fetched from `/colormaps/{id}` — these tables only drive the legends
/// and the offline plasma fallback, so this is the ONE place to update when the
/// server stops change.
enum ServerColormapStops {
    /// (dBZ bin, hex) — the plasma radar stops. Index 0 (dry) is transparent.
    static let radar: [(dbz: Double, hex: Int)] = [
        (1, 0x99ffff),    // drizzle
        (5.5, 0x32ffff), (10, 0x00caca), (14.5, 0x009934), (19, 0x4cbf19),
        (23.5, 0x98cb03), (28, 0xcce603), (32.5, 0xffff00), (37, 0xffc400),
        (41.5, 0xff8901), (46, 0xff0000), (50.5, 0xb40000), (55, 0x4848ff),
        (60, 0x0000c9), (65, 0x990199),
        (75, 0xfe33ff),   // extreme / hail
    ]

    /// −40 °C … +50 °C, 5 °C per stop.
    static let temperature: [Int] = [
        0x3f49b3, 0x4263d8, 0x3f7df1, 0x3896f9, 0x2bb1ef, 0x1ec9d8, 0x20dbbf,
        0x25eca5, 0xd2e92a, 0xe3d630, 0xf0c331, 0xf7ad2b, 0xf89525, 0xf77b1a,
        0xed610e, 0xe14906, 0xd13503, 0xbe2400, 0xa91500,
    ]

    /// 0 … ≥8 m/s, 1 m/s per stop.
    static let wind: [Int] = [
        0xf7fcff, 0xd2ddf2, 0xadbfe5, 0x9a9edc, 0x8a7fcf, 0x795eb5, 0x693e9a,
        0x581d77, 0x4a0059,
    ]

    /// (hPa, hex) — MSLP diverging stops (Crameri "vik", neutral ≈ 1013 hPa).
    /// Unevenly spaced; the value-grid index span is 930…1070 hPa (ends clamp).
    static let pressure: [(hpa: Double, hex: Int)] = [
        (950, 0x001261), (960, 0x023175), (970, 0x055189), (980, 0x2575a1),
        (990, 0x64a0be), (1000, 0xa3c7d9), (1005, 0xc3dae5), (1010, 0xe0e6e9),
        (1013, 0xece5e0), (1016, 0xeed9cd), (1020, 0xe6c4b0), (1025, 0xdbaa8d),
        (1030, 0xd0906b), (1040, 0xbb602d), (1050, 0x892606), (1060, 0x590008),
    ]

    /// Storm-cell marker steps (peak intensity → dot color), mirror of the
    /// `intensityColor` expression in WeatherMapView's cell layer. Labels reuse the
    /// radar legend's localization keys.
    static let stormCellSteps: [(hex: Int, label: String)] = [
        (0x00CACA, "Leicht"),
        (0xFFFF00, "Mäßig"),
        (0xFF0000, "Stark"),
        (0xFE33FF, "Extrem"),
    ]
}

enum WeatherColormap {
    case radar, temperature, wind, pressure

    // Colors ordered from minimum → maximum value
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
        case .pressure:
            // Legend spans the stop range 950…1060 hPa; fraction = (hPa − 950) / 110.
            return [
                (0.000, "950"),
                (0.182, "970"),
                (0.364, "990"),
                (0.545, "1010"),
                (0.727, "1030"),
                (1.000, "1060"),
            ]
        }
    }

    var unit: String {
        switch self {
        case .radar:       return "mm/h"
        case .temperature: return "°C"
        case .wind:        return "m/s"
        case .pressure:    return "hPa"
        }
    }

    // Gradient stops: evenly spaced (min at 0, max at 1). Pressure stops are
    // unevenly spaced in hPa, so their locations come from the value positions.
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

/// Compact key for the cell markers' peak-intensity colors — the dots alone don't
/// explain themselves. Same visual family as `ColormapVerticalLegend`.
struct StormCellLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Regenzellen")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(ServerColormapStops.stormCellSteps.enumerated()), id: \.offset) { _, step in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hex: step.hex))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                    Text(LocalizedStringKey(step.label))
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
