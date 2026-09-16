import Foundation

// MARK: - Value grid palette

/// Local fallback for the server `/colormaps/plasma` palette — kept in sync with
/// oscar-server's `Colormaps.plasma` so on-device rendering matches the raster path
/// when the palette endpoint is unreachable. idx 0 = transparent; sqrt-spaced.
enum RadarPlasma {
    static let colormapId = "plasma"
    private struct Stop { let value: Double; let color: PixelRGBA }

    private static func colorHex(_ hex: Int) -> PixelRGBA {
        PixelRGBA(r: UInt8((hex >> 16) & 255), g: UInt8((hex >> 8) & 255), b: UInt8(hex & 255), a: 255)
    }
    private static func mmPer5(_ hourly: Double) -> Double { hourly / 12 }
    private static func dbzToMmH(_ dbz: Double) -> Double {
        let t: [(Double, Double)] = [(5, 0.07), (10, 0.15), (15, 0.3), (20, 0.6), (25, 1.3),
            (30, 2.7), (35, 5.6), (40, 11.53), (45, 23.7), (50, 48.6), (55, 100), (60, 205), (65, 421)]
        if dbz <= t[0].0 { return t[0].1 }
        for p in zip(t, t.dropFirst()) where dbz <= p.1.0 {
            return p.0.1 + (p.1.1 - p.0.1) * (dbz - p.0.0) / (p.1.0 - p.0.0)
        }
        let p = (t[t.count - 2], t[t.count - 1])
        return p.0.1 + (p.1.1 - p.0.1) * (dbz - p.0.0) / (p.1.0 - p.0.0)
    }
    private static let stops: [Stop] = {
        [Stop(value: 0, color: PixelRGBA(r: 0, g: 0, b: 0, a: 0))]
            + ServerColormapStops.radar.map {
                Stop(value: mmPer5(dbzToMmH($0.dbz)), color: colorHex($0.hex))
            }
    }()
    private static let dbzMax = 85.0

    private static func sample(_ value: Double) -> PixelRGBA {
        guard let first = stops.first, let last = stops.last else { return PixelRGBA(r: 0, g: 0, b: 0, a: 0) }
        if value <= first.value { return first.color }
        if value >= last.value { return last.color }
        for p in zip(stops, stops.dropFirst()) where value >= p.0.value && value < p.1.value {
            let f = (value - p.0.value) / (p.1.value - p.0.value)
            func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
                UInt8(clamping: Int((Double(a) + f * (Double(b) - Double(a))).rounded()))
            }
            return PixelRGBA(r: mix(p.0.color.r, p.1.color.r), g: mix(p.0.color.g, p.1.color.g),
                             b: mix(p.0.color.b, p.1.color.b), a: mix(p.0.color.a, p.1.color.a))
        }
        return last.color
    }

    static func buildPalette() -> [PixelRGBA] {
        var pal = [PixelRGBA](repeating: PixelRGBA(r: 0, g: 0, b: 0, a: 0), count: 256)
        for i in 1..<256 {
            pal[i] = sample(mmPer5(dbzToMmH(Double(i) / 255 * dbzMax)))
        }
        return pal
    }
}
