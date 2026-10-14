import CoreLocation
import Foundation
import UIKit

extension RadarSnapshotRenderer {
    // MARK: - Storm cells (server /radar/{region}/cells, SCIT tracks)

    struct WidgetStormCell {
        let center: CLLocationCoordinate2D
        let peakMmh: Double
        let velocityKmh: Double
        let path: [CLLocationCoordinate2D]
        let footprint: [CLLocationCoordinate2D]
    }

    static func stormCells(
        region: RadarRegion, around center: CLLocationCoordinate2D
    ) async -> [WidgetStormCell] {
        guard let collection = try? await APIClient.shared.stormCells(
            region: region.pathComponent, profile: .snapshot)
        else { return [] }

        let cull = boundingBox(around: center, spanMeters: mapSpanMeters * 1.6)
        func coordinate(_ pair: [Double]) -> CLLocationCoordinate2D? {
            pair.count == 2
                ? CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0]) : nil
        }
        return collection.features.compactMap { feature in
            guard feature.geometry.coordinates.count == 2 else { return nil }
            let cellCenter = CLLocationCoordinate2D(
                latitude: feature.geometry.coordinates[1],
                longitude: feature.geometry.coordinates[0])
            guard cull.contains(cellCenter) else { return nil }
            return WidgetStormCell(
                center: cellCenter,
                peakMmh: feature.properties.peak_mmh,
                velocityKmh: feature.properties.velocity_kmh,
                path: feature.properties.path.compactMap(coordinate),
                footprint: (feature.properties.footprint ?? []).compactMap(coordinate))
        }
    }

    static func drawStormCells(_ cells: [WidgetStormCell], frame: MercatorFrame) {
        for cell in cells {
            let color = intensityColor(peakMmh: cell.peakMmh)

            if cell.footprint.count >= 4 {
                let hull = UIBezierPath()
                for (index, coordinate) in cell.footprint.enumerated() {
                    let point = frame.point(for: coordinate)
                    index == 0 ? hull.move(to: point) : hull.addLine(to: point)
                }
                hull.close()
                color.withAlphaComponent(0.15).setFill()
                hull.fill()
                color.withAlphaComponent(0.75).setStroke()
                hull.lineWidth = 1
                hull.stroke()
            }

            let trackPoints = [cell.center] + cell.path
            if cell.velocityKmh >= 3, trackPoints.count >= 2 {
                let track = UIBezierPath()
                track.move(to: frame.point(for: trackPoints[0]))
                for coordinate in trackPoints.dropFirst() {
                    track.addLine(to: frame.point(for: coordinate))
                }
                track.setLineDash([3, 2], count: 2, phase: 0)
                track.lineWidth = 1.5
                UIColor.white.withAlphaComponent(0.75).setStroke()
                track.stroke()
            }

            let point = frame.point(for: cell.center)
            let marker = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            color.setFill()
            UIBezierPath(ovalIn: marker).fill()
            let outline = UIBezierPath(ovalIn: marker)
            UIColor.white.withAlphaComponent(0.9).setStroke()
            outline.lineWidth = 1.5
            outline.stroke()
        }
    }

    private static func intensityColor(peakMmh: Double) -> UIColor {
        switch peakMmh {
        case ..<2: UIColor(red: 0, green: 0.79, blue: 0.79, alpha: 1)
        case ..<10: UIColor(red: 1, green: 1, blue: 0, alpha: 1)
        case ..<50: UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        default: UIColor(red: 0.996, green: 0.2, blue: 1, alpha: 1)
        }
    }
}
