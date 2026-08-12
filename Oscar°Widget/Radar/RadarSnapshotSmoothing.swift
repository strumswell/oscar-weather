import Foundation
import UIKit

extension RadarSnapshotRenderer {
    // MARK: - Smoothing (data-space, mirrors the fullscreen layer)

    /// The app's "Weichzeichnen", CPU edition. The fullscreen Metal layer samples
    /// the value grid with a bicubic B-spline and colormaps AFTER interpolation
    /// through a premultiplied palette LUT with linear blending. Blurring the
    /// colormapped tiles instead looks visibly different (off-palette color blends,
    /// softened alpha rims), so this reverses the tiles to palette indices, runs
    /// the same B-spline resample in data space, and recolormaps.
    private static var cachedPalettes: [String: [PixelRGBA]] = [:]

    static func palette(id: String) async -> [PixelRGBA]? {
        if let cached = cachedPalettes[id] { return cached }
        guard let data = try? await APIClient.shared.colormap(id: id, profile: .snapshot),
              data.count >= 256 * 4 else { return nil }
        let palette = (0..<256).map { entry -> PixelRGBA in
            let o = entry * 4
            return PixelRGBA(r: data[o], g: data[o + 1], b: data[o + 2], a: data[o + 3])
        }
        cachedPalettes[id] = palette
        return palette
    }

    static func dataSmoothedOverlay(
        tiles: [OverlayTile], frame: MercatorFrame, palette: [PixelRGBA]
    ) -> UIImage? {
        guard let zoom = tiles.first?.zoom, !tiles.isEmpty else { return nil }
        let n = pow(2, Double(zoom))

        // Premultiplied palette, like the Metal layer's LUT texture — index
        // reversal and linear blending both happen in premultiplied space.
        let premul: [(r: Double, g: Double, b: Double, a: Double)] = palette.map { entry in
            let a = Double(entry.a) / 255
            return (Double(entry.r) * a, Double(entry.g) * a, Double(entry.b) * a, Double(entry.a))
        }
        var reverseLUT: [UInt32: UInt8] = [:]
        for (index, entry) in premul.enumerated().reversed() {
            let key = UInt32(entry.r.rounded()) << 24 | UInt32(entry.g.rounded()) << 16
                | UInt32(entry.b.rounded()) << 8 | UInt32(entry.a.rounded())
            reverseLUT[key] = UInt8(index)
        }

        // Stitch the tiles' index planes into one mosaic (0 = no data/dry).
        let minX = tiles.map(\.tx).min()!, maxX = tiles.map(\.tx).max()!
        let minY = tiles.map(\.ty).min()!, maxY = tiles.map(\.ty).max()!
        let mosaicW = (maxX - minX + 1) * 256
        let mosaicH = (maxY - minY + 1) * 256
        var mosaic = [UInt8](repeating: 0, count: mosaicW * mosaicH)
        var nearestMemo: [UInt32: UInt8] = [:]
        for tile in tiles {
            guard let rgba = rgbaPlane(from: tile.image) else { continue }
            let originX = (tile.tx - minX) * 256
            let originY = (tile.ty - minY) * 256
            for py in 0..<256 {
                let src = py * 256 * 4
                let dst = (originY + py) * mosaicW + originX
                for px in 0..<256 {
                    let o = src + px * 4
                    let a = rgba[o + 3]
                    if a == 0 { continue }
                    let key = UInt32(rgba[o]) << 24 | UInt32(rgba[o + 1]) << 16
                        | UInt32(rgba[o + 2]) << 8 | UInt32(a)
                    if let index = reverseLUT[key] {
                        mosaic[dst + px] = index
                    } else if let index = nearestMemo[key] {
                        mosaic[dst + px] = index
                    } else {
                        // Off-palette color (server-side resampling rounding):
                        // nearest premultiplied entry, memoized per distinct color.
                        var best = 0
                        var bestDistance = Double.infinity
                        for (index, entry) in premul.enumerated() {
                            let dr = entry.r - Double(rgba[o])
                            let dg = entry.g - Double(rgba[o + 1])
                            let db = entry.b - Double(rgba[o + 2])
                            let da = entry.a - Double(a)
                            let distance = dr * dr + dg * dg + db * db + da * da
                            if distance < bestDistance {
                                bestDistance = distance
                                best = index
                            }
                        }
                        nearestMemo[key] = UInt8(best)
                        mosaic[dst + px] = UInt8(best)
                    }
                }
            }
        }

        // Resample in data space at composite resolution: bicubic B-spline over
        // the index mosaic (Sigg & Hadwiger weights, same as the shader), then
        // linear palette blend — colormap strictly after interpolation.
        let outW = Int(frame.size.width * compositeScale)
        let outH = Int(frame.size.height * compositeScale)
        guard outW > 0, outH > 0 else { return nil }
        var out = [UInt8](repeating: 0, count: outW * outH * 4)

        @inline(__always) func bsplineWeights(_ t: Double) -> (Double, Double, Double, Double) {
            let t2 = t * t, t3 = t2 * t
            return ((1 - 3 * t + 3 * t2 - t3) / 6,
                    (4 - 6 * t2 + 3 * t3) / 6,
                    (1 + 3 * t + 3 * t2 - 3 * t3) / 6,
                    t3 / 6)
        }

        mosaic.withUnsafeBufferPointer { indices in
            out.withUnsafeMutableBufferPointer { pixels in
                for py in 0..<outH {
                    let wy = frame.y0 + (Double(py) + 0.5) / Double(outH) * (frame.y1 - frame.y0)
                    let my = (wy * n - Double(minY)) * 256 - 0.5
                    guard my > -1, my < Double(mosaicH) else { continue }
                    let iy = Int(my.rounded(.down))
                    let (wy0, wy1, wy2, wy3) = bsplineWeights(my - Double(iy))

                    for px in 0..<outW {
                        let wx = frame.x0 + (Double(px) + 0.5) / Double(outW) * (frame.x1 - frame.x0)
                        let mx = (wx * n - Double(minX)) * 256 - 0.5
                        guard mx > -1, mx < Double(mosaicW) else { continue }
                        let ix = Int(mx.rounded(.down))
                        let (wx0, wx1, wx2, wx3) = bsplineWeights(mx - Double(ix))

                        @inline(__always) func sampledRow(_ row: Int) -> Double {
                            let sy = min(max(iy - 1 + row, 0), mosaicH - 1)
                            let rowBase = sy * mosaicW
                            let x0 = min(max(ix - 1, 0), mosaicW - 1)
                            let x1 = min(max(ix, 0), mosaicW - 1)
                            let x2 = min(max(ix + 1, 0), mosaicW - 1)
                            let x3 = min(max(ix + 2, 0), mosaicW - 1)
                            return wx0 * Double(indices[rowBase + x0])
                                + wx1 * Double(indices[rowBase + x1])
                                + wx2 * Double(indices[rowBase + x2])
                                + wx3 * Double(indices[rowBase + x3])
                        }
                        let value = wy0 * sampledRow(0) + wy1 * sampledRow(1)
                            + wy2 * sampledRow(2) + wy3 * sampledRow(3)
                        guard value > 0.01 else { continue }

                        let clamped = min(max(value, 0), 255)
                        let i0 = Int(clamped)
                        let i1 = min(255, i0 + 1)
                        let f = clamped - Double(i0)
                        let e0 = premul[i0], e1 = premul[i1]
                        let o = (py * outW + px) * 4
                        pixels[o]     = UInt8((e0.r + (e1.r - e0.r) * f).rounded())
                        pixels[o + 1] = UInt8((e0.g + (e1.g - e0.g) * f).rounded())
                        pixels[o + 2] = UInt8((e0.b + (e1.b - e0.b) * f).rounded())
                        pixels[o + 3] = UInt8((e0.a + (e1.a - e0.a) * f).rounded())
                    }
                }
            }
        }

        let cgImage: CGImage? = out.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: outW, height: outH, bitsPerComponent: 8,
                bytesPerRow: outW * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }
        guard let cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: compositeScale, orientation: .up)
    }

    /// Decode a 256 px tile into premultiplied RGBA bytes.
    private static func rgbaPlane(from image: UIImage) -> [UInt8]? {
        guard let cgImage = image.cgImage else { return nil }
        var rgba = [UInt8](repeating: 0, count: 256 * 256 * 4)
        let ok = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: 256, height: 256, bitsPerComponent: 8,
                bytesPerRow: 256 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: 256, height: 256))
            return true
        }
        return ok ? rgba : nil
    }
}
