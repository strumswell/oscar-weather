import CoreLocation
import Foundation
import UIKit

extension RadarSnapshotRenderer {
    // MARK: - Motion arrows (shares RadarArrowGeometry with WeatherMapView)

    /// One arrow per coarse motion cell that carries precipitation and non-trivial
    /// flow, culled to the widget's viewport. Identical placement math to the app
    /// (RadarArrowGeometry); only the precip gate differs (raster-tile alpha
    /// instead of the value grid).
    static func arrowFeatures(
        motion: RadarMotionData, fieldIndex: Int, bounds: OscarRadarBounds,
        cull: GeoBox, gate: PrecipGate?
    ) -> [RadarArrow] {
        guard let gate else { return [] }
        let cols = motion.cols, rows = motion.rows
        let coordinate = RadarArrowGeometry.coordinateMapper(bounds: bounds)

        var arrows: [RadarArrow] = []
        for cell in RadarArrowGeometry.arrowCells(motion: motion, fieldIndex: fieldIndex, bounds: bounds) {
            guard cull.contains(cell.coordinate) else { continue }

            // ≥2 of 25 subsampled points inside the cell footprint carry precip —
            // the app's cellHasPrecip rule, sampled from the gate tiles.
            var hits = 0
            subsample: for sy in 0..<5 {
                for sx in 0..<5 {
                    let x = cell.uvX + (Double(sx) / 4 - 0.5) / Double(cols)
                    let y = cell.uvY + (Double(sy) / 4 - 0.5) / Double(rows)
                    guard x >= 0, x <= 1, y >= 0, y <= 1 else { continue }
                    if gate.hasPrecip(at: coordinate(x, y)) {
                        hits += 1
                        if hits >= 2 { break subsample }
                    }
                }
            }
            guard hits >= 2 else { continue }

            arrows.append(RadarArrow(coordinate: cell.coordinate, rotation: cell.rotation, scale: cell.scale))
            if arrows.count >= 80 { break }
        }
        return arrows
    }

    // MARK: - Precip gate (alpha-sampled radar tiles)

    /// A few 256 px radar tiles around the viewport, kept as alpha planes; answers
    /// "is there precipitation at this coordinate" for the arrow gate. Bounded by
    /// construction: at most 6 tiles ≈ 400 KB transient.
    struct PrecipGate {
        let zoom: Int
        let tiles: [Int: [UInt8]] // key: x << 16 | y, value: 256×256 alpha plane

        static let gateZoom = 8

        static func load(
            around center: CLLocationCoordinate2D, spanMeters: Double,
            region: RadarRegion, frameKey: String
        ) async -> PrecipGate? {
            let box = boundingBox(around: center, spanMeters: spanMeters)
            let x0 = WebMercator.tileX(longitude: box.west, zoom: gateZoom)
            let x1 = WebMercator.tileX(longitude: box.east, zoom: gateZoom)
            let y0 = WebMercator.tileY(latitude: box.north, zoom: gateZoom)
            let y1 = WebMercator.tileY(latitude: box.south, zoom: gateZoom)
            guard (x1 - x0 + 1) * (y1 - y0 + 1) <= 6 else { return nil }

            var tiles: [Int: [UInt8]] = [:]
            for x in x0...x1 {
                for y in y0...y1 {
                    guard let data = try? await APIClient.shared.radarTile(
                        region: region.pathComponent, key: frameKey, z: gateZoom, x: x, y: y,
                        profile: .snapshot),
                        let alpha = alphaPlane(from: data) else { continue }
                    tiles[x << 16 | y] = alpha
                }
            }
            return tiles.isEmpty ? nil : PrecipGate(zoom: gateZoom, tiles: tiles)
        }

        func hasPrecip(at coordinate: CLLocationCoordinate2D) -> Bool {
            let scale = pow(2, Double(zoom)) * 256
            let worldX = WebMercator.unitX(longitude: coordinate.longitude) * scale
            let worldY = WebMercator.unitY(latitude: coordinate.latitude) * scale
            let x = Int(worldX / 256), y = Int(worldY / 256)
            guard let alpha = tiles[x << 16 | y] else { return false }
            let px = min(255, max(0, Int(worldX) - x * 256))
            let py = min(255, max(0, Int(worldY) - y * 256))
            return alpha[py * 256 + px] > 16
        }

        /// Decode a 256 px tile and keep only its alpha channel (dry = transparent).
        private static func alphaPlane(from data: Data) -> [UInt8]? {
            guard let image = UIImage(data: data)?.cgImage else { return nil }
            var rgba = [UInt8](repeating: 0, count: 256 * 256 * 4)
            let ok = rgba.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(
                    data: raw.baseAddress, width: 256, height: 256, bitsPerComponent: 8,
                    bytesPerRow: 256 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256))
                return true
            }
            guard ok else { return nil }
            return (0..<256 * 256).map { rgba[$0 * 4 + 3] }
        }
    }
}
