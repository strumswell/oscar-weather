//
//  RadarMotionArrows.swift
//  Oscar°
//
//  Client-side motion arrows for the paused radar, built from the /motion flow
//  field plus the frame's in-RAM value grid (used by WeatherMapView's
//  syncArrowLayer). Placement math and the arrow icon live in RadarArrowGeometry,
//  shared with the widget's CPU compositor (RadarSnapshotRenderer).
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
        let cellW = 1.0 / Double(motion.cols)
        let cellH = 1.0 / Double(motion.rows)
        return RadarArrowGeometry.arrowCells(motion: motion, fieldIndex: fieldIndex, bounds: bounds)
            .compactMap { cell in
                guard cellHasPrecip(grid: grid, uvX: cell.uvX, uvY: cell.uvY,
                                    cellW: cellW, cellH: cellH) else { return nil }
                let feature = MLNPointFeature()
                feature.coordinate = cell.coordinate
                feature.attributes = [
                    "rotation": cell.rotation,
                    "scale": cell.scale,
                ]
                return feature
            }
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
}
