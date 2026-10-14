import CoreLocation
import Foundation
import UIKit

extension OscarRadarBounds {
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= south && coordinate.latitude <= north
            && coordinate.longitude >= west && coordinate.longitude <= east
    }
}

extension RadarSnapshotRenderer {
    // MARK: - Geo helpers

    struct MercatorFrame {
        let x0, x1: Double
        let y0, y1: Double
        let size: CGSize

        init(bounds: OscarRadarBounds, size: CGSize) {
            x0 = WebMercator.unitX(longitude: bounds.west)
            x1 = WebMercator.unitX(longitude: bounds.east)
            y0 = WebMercator.unitY(latitude: bounds.north)
            y1 = WebMercator.unitY(latitude: bounds.south)
            self.size = size
        }

        func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
            point(forWorldX: WebMercator.unitX(longitude: coordinate.longitude),
                  worldY: WebMercator.unitY(latitude: coordinate.latitude))
        }

        func point(forWorldX wx: Double, worldY wy: Double) -> CGPoint {
            CGPoint(
                x: (wx - x0) / (x1 - x0) * size.width,
                y: (wy - y0) / (y1 - y0) * size.height
            )
        }
    }

    nonisolated static func fittedBounds(
        around center: CLLocationCoordinate2D, spanMeters: Double, size: CGSize
    ) -> OscarRadarBounds {
        let box = boundingBox(around: center, spanMeters: spanMeters)
        var west = WebMercator.unitX(longitude: box.west)
        var east = WebMercator.unitX(longitude: box.east)
        var north = WebMercator.unitY(latitude: box.north)
        var south = WebMercator.unitY(latitude: box.south)
        let aspect = Double(size.width / size.height)
        let width = east - west, height = south - north
        if width / height < aspect {
            let extra = (height * aspect - width) / 2
            west -= extra
            east += extra
        } else {
            let extra = (width / aspect - height) / 2
            north -= extra
            south += extra
        }
        return OscarRadarBounds(
            north: WebMercator.latitude(fromUnitY: north), south: WebMercator.latitude(fromUnitY: south),
            west: WebMercator.longitude(fromUnitX: west), east: WebMercator.longitude(fromUnitX: east)
        )
    }

    nonisolated static func boundingBox(around center: CLLocationCoordinate2D, spanMeters: Double) -> OscarRadarBounds {
        let halfLat = spanMeters / 2 / 111_320
        let halfLon = spanMeters / 2 / (111_320 * max(0.2, cos(center.latitude * .pi / 180)))
        return OscarRadarBounds(
            north: center.latitude + halfLat, south: center.latitude - halfLat,
            west: center.longitude - halfLon, east: center.longitude + halfLon
        )
    }
}
