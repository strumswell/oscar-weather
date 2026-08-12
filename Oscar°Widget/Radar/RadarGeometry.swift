import CoreLocation
import Foundation
import UIKit

extension RadarSnapshotRenderer {
    // MARK: - Geo helpers

    struct GeoBox {
        let south, west, north, east: Double

        func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
            coordinate.latitude >= south && coordinate.latitude <= north
                && coordinate.longitude >= west && coordinate.longitude <= east
        }
    }

    /// Linear Web-Mercator mapping between a coordinate rectangle and composite
    /// points — the CPU analog of the basemap snapshot's point conversion.
    struct MercatorFrame {
        let x0, x1: Double // world-fraction X at west/east
        let y0, y1: Double // world-fraction Y at north/south
        let size: CGSize

        init(bounds: GeoBox, size: CGSize) {
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

    /// The coordinate rectangle a bounds-fitted snapshot of `size` would show: the
    /// 65 km box extended along one axis to the size's aspect ratio in Mercator
    /// space. Used only when no prerendered basemap exists yet.
    nonisolated static func fittedBounds(
        around center: CLLocationCoordinate2D, spanMeters: Double, size: CGSize
    ) -> GeoBox {
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
        return GeoBox(
            south: WebMercator.latitude(fromUnitY: south), west: WebMercator.longitude(fromUnitX: west),
            north: WebMercator.latitude(fromUnitY: north), east: WebMercator.longitude(fromUnitX: east)
        )
    }

    nonisolated static func boundingBox(around center: CLLocationCoordinate2D, spanMeters: Double) -> GeoBox {
        let halfLat = spanMeters / 2 / 111_320
        let halfLon = spanMeters / 2 / (111_320 * max(0.2, cos(center.latitude * .pi / 180)))
        return GeoBox(
            south: center.latitude - halfLat, west: center.longitude - halfLon,
            north: center.latitude + halfLat, east: center.longitude + halfLon
        )
    }
}
