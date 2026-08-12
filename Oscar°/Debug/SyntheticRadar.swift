import Foundation
import ImageIO
import UIKit

// MARK: - Synthetic radar (oscar-server frames/grid/tiles/motion/cells)

/// Deterministic fake precipitation for the map and widget scenes: a SW→NE
/// frontal band with embedded convective cores over Leipzig, built from
/// hash-based value noise (structure modeled on the OPERA composite). The
/// same field feeds the fullscreen map's value grid, the widget's raster
/// tiles, and the motion arrows, advected per frame so the timeline animates.
enum SyntheticRadar {
    static let north = 55.6, south = 46.0, west = 3.6, east = 17.8
    /// Served frames mirror the DWD RV timeline oscar-server relays from
    /// Bright Sky: the observed past hour plus pre-extrapolated forecast
    /// frames two hours out, all in 5-minute steps. The key encodes the offset.
    static let offsets = Array(stride(from: -60, through: 120, by: 5))
    static let gridWidth = 280, gridHeight = 240

    static func key(_ offset: Int) -> String { "fx\(offset)" }
    static func offsetMinutes(fromKey key: String) -> Double? {
        key.hasPrefix("fx") ? Double(key.dropFirst(2)) : nil
    }

    // MARK: JSON endpoints

    static func framesJSON() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        let now = Date.now
        let bounds: [String: Any] = ["north": north, "south": south, "west": west, "east": east]
        return [
            "generated_at": formatter.string(from: now),
            "frame_count": offsets.count,
            "frames": offsets.enumerated().map { index, offset in
                [
                    "key": key(offset),
                    "timestamp": formatter.string(from: now.addingTimeInterval(Double(offset) * 60)),
                    "source": "dwd",
                    "index": index,
                    "is_forecast": offset > 0,
                ]
            },
            "bounds": bounds,
            "image_bounds": bounds,
        ]
    }

    static func cellsJSON() -> [String: Any] {
        ["type": "FeatureCollection", "features": [] as [Any]]
    }

    /// One shared coarse flow field, SW→NE like the band's advection.
    static func motionJSON() -> [String: Any] {
        let cols = 8, rows = 8
        var values = [Int16](repeating: 70, count: cols * rows)          // u: east (×0.05 px/step)
        values.append(contentsOf: [Int16](repeating: -40, count: cols * rows))  // v: north
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        let pairs: [[String: Any]] = (0..<(offsets.count - 1)).map {
            ["from": key(offsets[$0]), "to": key(offsets[$0 + 1]), "field": 0, "gap_minutes": 5]
        }
        return [
            "cols": cols, "rows": rows,
            "overview_width": gridWidth, "overview_height": gridHeight,
            "scale": 0.05, "step_minutes": 5,
            "fields": [data.base64EncodedString()],
            "pairs": pairs,
        ]
    }

    // MARK: Field

    private static func hash(_ x: Int, _ y: Int) -> Double {
        var v = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        v ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F
        v = (v ^ (v >> 31)) &* 0xD6E8_FEB8_6659_FD93
        v ^= v >> 32
        return Double(v % 1_000_000) / 1_000_000
    }

    private static func valueNoise(_ x: Double, _ y: Double) -> Double {
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
        let a = hash(x0, y0), b = hash(x0 + 1, y0)
        let c = hash(x0, y0 + 1), d = hash(x0 + 1, y0 + 1)
        return a + (b - a) * smooth(fx) + (c - a) * smooth(fy)
            + (a - b - c + d) * smooth(fx) * smooth(fy)
    }

    private static func fbm(_ x: Double, _ y: Double) -> Double {
        var amplitude = 0.5, frequency = 1.0, total = 0.0
        for _ in 0..<4 {
            total += amplitude * valueNoise(x * frequency, y * frequency)
            amplitude *= 0.5
            frequency *= 2.1
        }
        return total
    }

    /// Cloud opacity 0…1: a much wider deck around the rain band (rain implies
    /// cloud; cloud reaches far beyond the rain), advected with the same flow —
    /// so the clouds fixture visibly extends past the radar echoes.
    static func cloudOpacity(lat: Double, lon: Double, minutes t: Double) -> Double {
        let ax = lon - t * 0.011
        let ay = lat - t * 0.006
        let d = ((ay - 51.1) - (ax - 12.4) * 0.55) / 4.2
        let envelope = exp(-d * d)
        let deck = max(0, envelope * (fbm(ax * 0.8 + 12, ay * 0.8 + 31) * 1.6 - 0.25))
        return min(1, deck + intensity(lat: lat, lon: lon, minutes: t) * 1.5)
    }

    /// Intensity 0…1 at a coordinate, advected SW→NE over time.
    static func intensity(lat: Double, lon: Double, minutes t: Double) -> Double {
        let ax = lon - t * 0.011
        let ay = lat - t * 0.006
        let d = ((ay - 51.1) - (ax - 12.4) * 0.55) / 1.9
        let along = (ax - 12.4) * 0.876 + (ay - 51.1) * 0.481
        let envelope = exp(-d * d) * exp(-pow(along / 5.0, 2))
        let n1 = fbm(ax * 1.1 + 40, ay * 1.1 - 7)
        let warp = fbm(ax * 2.3 - 11, ay * 2.3 + 23)
        let n2 = fbm(ax * 3.1 + warp * 1.7 + 90, ay * 3.1 + warp * 1.7 - 55)
        let core = max(0, n1 * 0.55 + n2 * 0.65 - 0.52) * 2.4
        let scattered = max(0, n2 - 0.72) * 1.8
        return min(1, envelope * core + scattered * 0.35)
    }

    // MARK: Mercator helpers

    private static func mercY(_ lat: Double) -> Double {
        log(tan(.pi / 4 + lat * .pi / 360))
    }
    private static func latFromMercY(_ y: Double) -> Double {
        (2 * atan(exp(y)) - .pi / 2) * 180 / .pi
    }

    // MARK: Value grid (fullscreen map's Metal layer)

    /// URLProtocol loads on arbitrary threads — guard the render caches.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var gridCache: [String: Data] = [:]

    /// Single-channel 8-bit grid in Web Mercator rows (row 0 = north), like the
    /// server's lossless WebP — `UIImage(data:)` decodes PNG just the same.
    /// Plain style: 0 = dry, values over the plasma dBZ ramp. Typed: rain span
    /// 1…153 (a July scene has no snow or ice).
    static func gridPNG(frameKey: String, typed: Bool) -> Data {
        let cacheKey = "\(frameKey)|\(typed)"
        cacheLock.lock()
        if let cached = gridCache[cacheKey] { cacheLock.unlock(); return cached }
        cacheLock.unlock()
        let t = offsetMinutes(fromKey: frameKey) ?? 0
        let w = gridWidth, h = gridHeight
        var pixels = [UInt8](repeating: 0, count: w * h)
        let mN = mercY(north), mS = mercY(south)
        for j in 0..<h {
            let lat = latFromMercY(mN + (mS - mN) * Double(j) / Double(h))
            for i in 0..<w {
                let lon = west + (east - west) * Double(i) / Double(w)
                let v = intensity(lat: lat, lon: lon, minutes: t)
                guard v >= 0.02 else { continue }
                pixels[j * w + i] = typed
                    ? UInt8(1 + min(152, v * 152))
                    : UInt8(1 + min(219, v * 219))
            }
        }
        let png = grayPNG(pixels: pixels, width: w, height: h)
        cacheLock.lock()
        gridCache[cacheKey] = png
        cacheLock.unlock()
        return png
    }

    /// Clouds flavor of the value grid: opacity index 0…255 (the clouds palette
    /// contract), from `cloudOpacity`'s wider deck.
    static func cloudGridPNG(frameKey: String) -> Data {
        let cacheKey = "\(frameKey)|clouds"
        cacheLock.lock()
        if let cached = gridCache[cacheKey] { cacheLock.unlock(); return cached }
        cacheLock.unlock()
        let t = offsetMinutes(fromKey: frameKey) ?? 0
        let w = gridWidth, h = gridHeight
        var pixels = [UInt8](repeating: 0, count: w * h)
        let mN = mercY(north), mS = mercY(south)
        for j in 0..<h {
            let lat = latFromMercY(mN + (mS - mN) * Double(j) / Double(h))
            for i in 0..<w {
                let lon = west + (east - west) * Double(i) / Double(w)
                let v = cloudOpacity(lat: lat, lon: lon, minutes: t)
                guard v >= 0.03 else { continue }
                pixels[j * w + i] = UInt8(min(255, 40 + v * 215))
            }
        }
        let png = grayPNG(pixels: pixels, width: w, height: h)
        cacheLock.lock()
        gridCache[cacheKey] = png
        cacheLock.unlock()
        return png
    }

    private static func grayPNG(pixels: [UInt8], width: Int, height: Int) -> Data {
        var pixels = pixels
        let image = pixels.withUnsafeMutableBytes { raw -> CGImage? in
            let context = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
            return context?.makeImage()
        }
        guard let image else { return Data() }
        return UIImage(cgImage: image).pngData() ?? Data()
    }

    // MARK: Raster tiles (widget composite + precip gate)

    nonisolated(unsafe) private static var tileCache: [String: Data] = [:]

    /// The widget reverse-maps tile colors to palette indices through the
    /// server colormap (data-space smoothing), so tile pixels must BE palette
    /// entries — hand-approximated colors snap to wrong (purple) indices.
    /// Colormaps pass through the fixture server live; fetch the real plasma
    /// palette once and build tiles from it with the exact grid index math,
    /// which makes the widget match the fullscreen map by construction.
    nonisolated(unsafe) private static var cachedPalette: [UInt8]?
    private static func plasmaPalette() -> [UInt8] {
        cacheLock.lock()
        if let cached = cachedPalette { cacheLock.unlock(); return cached }
        cacheLock.unlock()
        final class Box: @unchecked Sendable { var data: [UInt8]? }
        let box = Box()
        if let url = URL(string: "\(radarBaseURL)/colormaps/plasma") {
            let semaphore = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data, data.count >= 256 * 4 { box.data = [UInt8](data.prefix(256 * 4)) }
                semaphore.signal()
            }.resume()
            _ = semaphore.wait(timeout: .now() + 10)
        }
        // Offline fallback: approximated plasma with a hard alpha ramp.
        let resolved = box.data ?? (0..<256).flatMap { i -> [UInt8] in
            guard i > 0 else { return [0, 0, 0, 0] }
            let t = Double(i - 1) / 254
            let (r, g, b) = plasma(t)
            return [UInt8(r), UInt8(g), UInt8(b), UInt8(min(235, 70 + t * 400))]
        }
        cacheLock.lock()
        cachedPalette = resolved
        cacheLock.unlock()
        return resolved
    }

    /// Raster tile like the server's: the value grid's palette index per
    /// pixel, colorized through the shared colormap (premultiplied).
    static func tilePNG(frameKey: String, z: Int, x: Int, y: Int) -> Data {
        let cacheKey = "\(frameKey)|\(z)/\(x)/\(y)"
        cacheLock.lock()
        if let cached = tileCache[cacheKey] { cacheLock.unlock(); return cached }
        cacheLock.unlock()
        let t = offsetMinutes(fromKey: frameKey) ?? 0
        let palette = plasmaPalette()
        let size = 256
        let n = pow(2.0, Double(z))
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for j in 0..<size {
            let yTile = (Double(y) + Double(j) / Double(size)) / n
            let lat = latFromMercY(.pi * (1 - 2 * yTile))
            for i in 0..<size {
                let lon = (Double(x) + Double(i) / Double(size)) / n * 360 - 180
                let v = intensity(lat: lat, lon: lon, minutes: t)
                guard v >= 0.02 else { continue }
                // Same index math as gridPNG, so tiles == fullscreen grid.
                let index = Int(1 + min(219, v * 219))
                let p = index * 4
                let o = (j * size + i) * 4
                // Straight (non-premultiplied) palette RGBA, exactly like the
                // server's tiles: PNG stores unpremultiplied, and the widget's
                // reverse LUT expects pixels that ARE palette entries.
                pixels[o] = palette[p]
                pixels[o + 1] = palette[p + 1]
                pixels[o + 2] = palette[p + 2]
                pixels[o + 3] = palette[p + 3]
            }
        }
        // Encode via ImageIO from a non-premultiplied CGImage — a CGContext
        // round-trip would premultiply and lose the exact palette values.
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent),
              let png = pngData(from: image) else {
            return Data()
        }
        cacheLock.lock()
        tileCache[cacheKey] = png
        cacheLock.unlock()
        return png
    }

    private static func pngData(from image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func plasma(_ v: Double) -> (Int, Int, Int) {
        let stops: [(Double, (Double, Double, Double))] = [
            (0.00, (13, 8, 135)), (0.25, (126, 3, 168)), (0.50, (204, 71, 120)),
            (0.75, (248, 149, 64)), (1.00, (240, 249, 33)),
        ]
        for i in 0..<(stops.count - 1) {
            let (a, ca) = stops[i], (b, cb) = stops[i + 1]
            if v <= b {
                let f = (v - a) / (b - a)
                return (Int(ca.0 + (cb.0 - ca.0) * f), Int(ca.1 + (cb.1 - ca.1) * f), Int(ca.2 + (cb.2 - ca.2) * f))
            }
        }
        return (240, 249, 33)
    }
}
