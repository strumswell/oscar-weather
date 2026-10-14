//
//  RadarSharedGeometry.swift
//  Oscar°
//
//  Web-Mercator math and motion-arrow geometry shared by the app's map layers
//  and the widget's CPU compositor (compiled into both targets).
//

import CoreLocation
import Foundation
import UIKit

// MARK: - Web Mercator

enum WebMercator {
    static let maxLatitude = 85.05112878

    // MARK: Unit square [0,1]² (+y = south)

    static func unitX(longitude: Double) -> Double {
        (longitude + 180) / 360
    }

    static func unitY(latitude: Double) -> Double {
        (1 - projectedY(latitude: latitude) / .pi) / 2
    }

    static func longitude(fromUnitX x: Double) -> Double {
        x * 360 - 180
    }

    static func latitude(fromUnitY y: Double) -> Double {
        latitude(fromProjectedY: .pi * (1 - 2 * y))
    }

    // MARK: Raw projected y in radians (+y = north)

    static func projectedY(latitude: Double) -> Double {
        log(tan(.pi / 4 + latitude * .pi / 360))
    }

    static func latitude(fromProjectedY y: Double) -> Double {
        (2 * atan(exp(y)) - .pi / 2) * 180 / .pi
    }

    // MARK: Tile indices

    static func tileX(longitude: Double, zoom: Int) -> Int {
        Int(floor(unitX(longitude: longitude) * pow(2, Double(zoom))))
    }

    static func tileY(latitude: Double, zoom: Int) -> Int {
        Int(floor(unitY(latitude: latitude) * pow(2, Double(zoom))))
    }
}

// MARK: - Motion-arrow geometry

enum RadarArrowGeometry {
    struct Cell {
        let uvX: Double
        let uvY: Double
        let coordinate: CLLocationCoordinate2D
        let rotation: Double
        let scale: Double
    }

    static func coordinateMapper(
        bounds: OscarRadarBounds
    ) -> (_ uvX: Double, _ uvY: Double) -> CLLocationCoordinate2D {
        let yNorth = WebMercator.projectedY(latitude: bounds.north)
        let ySouth = WebMercator.projectedY(latitude: bounds.south)
        return { uvX, uvY in
            let y = yNorth + uvY * (ySouth - yNorth)
            return CLLocationCoordinate2D(
                latitude: WebMercator.latitude(fromProjectedY: y),
                longitude: bounds.west + uvX * (bounds.east - bounds.west)
            )
        }
    }

    static func arrowCells(
        motion: RadarMotionData, fieldIndex: Int, bounds: OscarRadarBounds
    ) -> [Cell] {
        guard motion.fields.indices.contains(fieldIndex) else { return [] }
        let field = motion.fields[fieldIndex]
        let cols = motion.cols, rows = motion.rows
        guard field.count == cols * rows * 2 else { return [] }

        let coordinate = coordinateMapper(bounds: bounds)
        var cells: [Cell] = []
        cells.reserveCapacity(cols * rows / 8)
        for row in 0..<rows {
            for col in 0..<cols {
                guard (row + col) % 2 == 0 else { continue }
                let u = Double(field[row * cols + col])
                let v = Double(field[cols * rows + row * cols + col])
                let speed = (u * u + v * v).squareRoot()
                guard speed >= 0.8 else { continue }

                let uvX = (Double(col) + 0.5) / Double(cols)
                let uvY = (Double(row) + 0.5) / Double(rows)
                cells.append(Cell(
                    uvX: uvX, uvY: uvY,
                    coordinate: coordinate(uvX, uvY),
                    rotation: atan2(u, -v) * 180 / .pi,
                    scale: 0.6 + min(speed / 4, 1) * 0.55
                ))
            }
        }
        return cells
    }

    static func arrowImage() -> UIImage {
        let size = CGSize(width: 13, height: 18)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 6.5, y: 16.5))
        path.addLine(to: CGPoint(x: 6.5, y: 2))
        path.move(to: CGPoint(x: 3.8, y: 5.6))
        path.addLine(to: CGPoint(x: 6.5, y: 2))
        path.addLine(to: CGPoint(x: 9.2, y: 5.6))
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
