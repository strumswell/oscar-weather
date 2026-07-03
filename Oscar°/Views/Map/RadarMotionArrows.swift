//
//  RadarMotionArrows.swift
//  Oscar°
//
//  Client-side motion arrows for the paused radar, built from the /motion flow
//  field plus the frame's in-RAM value grid (used by WeatherMapView's
//  syncArrowLayer; RadarSnapshotRenderer in the widget carries a CPU port).
//

import CoreLocation
import MapLibre
import UIKit

enum RadarMotionArrows {
    /// One arrow per coarse motion cell whose footprint carries precipitation
    /// (subsampled 5×5 presence check on the frame grid) and whose flow is
    /// non-trivial. Cell centers share the overview's UV space with the frame
    /// grid; UV → lat/lon via the (mercator-aligned) image bounds.
    static func arrowFeatures(
        motion: RadarMotionData, fieldIndex: Int,
        grid: RadarGridPayload, bounds: OscarRadarBounds
    ) -> [MLNPointFeature] {
        guard motion.fields.indices.contains(fieldIndex) else { return [] }
        let field = motion.fields[fieldIndex]
        let cols = motion.cols, rows = motion.rows
        guard field.count == cols * rows * 2 else { return [] }

        func mercatorY(_ latitude: Double) -> Double {
            log(tan(.pi / 4 + latitude * .pi / 360))
        }
        let yNorth = mercatorY(bounds.north)
        let ySouth = mercatorY(bounds.south)

        var features: [MLNPointFeature] = []
        features.reserveCapacity(cols * rows / 8)
        for row in 0..<rows {
            for col in 0..<cols {
                // Checkerboard: half the cells, evenly spread — the full cell
                // pitch read as too busy.
                guard (row + col) % 2 == 0 else { continue }
                let u = Double(field[row * cols + col])
                let v = Double(field[cols * rows + row * cols + col])
                let speed = (u * u + v * v).squareRoot()
                guard speed >= 0.8 else { continue }

                let uvX = (Double(col) + 0.5) / Double(cols)
                let uvY = (Double(row) + 0.5) / Double(rows)
                guard cellHasPrecip(grid: grid, uvX: uvX, uvY: uvY,
                                    cellW: 1.0 / Double(cols), cellH: 1.0 / Double(rows)) else { continue }

                let feature = MLNPointFeature()
                let y = yNorth + uvY * (ySouth - yNorth)
                feature.coordinate = CLLocationCoordinate2D(
                    latitude: (2 * atan(exp(y)) - .pi / 2) * 180 / .pi,
                    longitude: bounds.west + uvX * (bounds.east - bounds.west))
                feature.attributes = [
                    // +u = east, +v = south → clockwise-from-north degrees.
                    "rotation": atan2(u, -v) * 180 / .pi,
                    // Slightly larger arrows for faster motion (0.6…1.15).
                    "scale": 0.6 + min(speed / 4, 1) * 0.55,
                ]
                features.append(feature)
            }
        }
        return features
    }

    /// ≥2 of 25 subsampled points inside the cell footprint carry a nonzero
    /// grid index (the client analog of the server's block-sum gate).
    private static func cellHasPrecip(
        grid: RadarGridPayload, uvX: Double, uvY: Double, cellW: Double, cellH: Double
    ) -> Bool {
        guard grid.width > 1, grid.height > 1 else { return false }
        var hits = 0
        for sy in 0..<5 {
            for sx in 0..<5 {
                let x = uvX + (Double(sx) / 4 - 0.5) * cellW
                let y = uvY + (Double(sy) / 4 - 0.5) * cellH
                guard x >= 0, x <= 1, y >= 0, y <= 1 else { continue }
                let px = Int(x * Double(grid.width - 1))
                let py = Int(y * Double(grid.height - 1))
                if grid.indices[py * grid.width + px] > 0 {
                    hits += 1
                    if hits >= 2 { return true }
                }
            }
        }
        return false
    }

    /// Thin north-pointing line arrow, black with a thin white border — the look
    /// of the old server-rendered vector tiles. Drawn as a stroked path twice:
    /// wider white underneath, thin black on top.
    static func arrowImage() -> UIImage {
        let size = CGSize(width: 13, height: 18)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 6.5, y: 16.5))        // tail
        path.addLine(to: CGPoint(x: 6.5, y: 2))        // tip
        path.move(to: CGPoint(x: 3.8, y: 5.6))         // head left
        path.addLine(to: CGPoint(x: 6.5, y: 2))
        path.addLine(to: CGPoint(x: 9.2, y: 5.6))      // head right
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setStroke()
            path.lineWidth = 2.6
            path.stroke()
            UIColor.black.setStroke()
            path.lineWidth = 1.1
            path.stroke()
        }
    }
}
