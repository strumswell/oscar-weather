import CoreLocation
import MapLibre
import Metal
import OSLog
import Observation
import SwiftUI
import UIKit

// MARK: Storm cells

extension WeatherMapView.Coordinator {
    /// Tracked precipitation cells (server `/radar/{region}/cells`), SCIT-style:
    /// the cell's footprint hull, its extrapolated one-hour track with +15-min
    /// tick marks and an arrowhead, a widening uncertainty cone, and a peak-
    /// intensity marker (the tap target). Features are rebuilt client-side from
    /// the GeoJSON properties (`path`/`footprint`), which MapLibre can't draw
    /// directly.
    func syncStormCells(style: MLNStyle, active: Bool, region: RadarRegion) {
        guard active else {
            removeStormCellLayers(from: style)
            return
        }

        let isStale = stormCellsFetchedAt.map { Date().timeIntervalSince($0) > 120 } ?? true
        if (isStale || stormCellsRegion != region), !isLoadingStormCells {
            isLoadingStormCells = true
            Task { @MainActor [weak self] in
                defer { self?.isLoadingStormCells = false }
                do {
                    let collection = try await APIClient.shared.stormCells(region: region.pathComponent)
                    guard let self, !self.isTornDown else { return }
                    self.stormCells = Self.parseStormCells(collection)
                    self.stormCellsFetchedAt = Date()
                    self.stormCellsRegion = region
                    if let style = self.mapView?.style {
                        self.removeStormCellLayers(from: style)
                    }
                    self.syncAll()
                } catch {
                    weatherMapLogger.error("Storm cell fetch failed: \(error.localizedDescription, privacy: .public)")
                    // Record the attempted region too, or a failed region switch
                    // would re-trigger the fetch on every sync with no backoff.
                    self?.stormCellsFetchedAt = Date()
                    self?.stormCellsRegion = region
                }
            }
        }

        guard style.source(withIdentifier: WeatherMapView.cellPointSourceID) == nil,
              let cells = stormCells
        else { return }

        let features = Self.buildStormCellFeatures(cells)

        let coneSource = MLNShapeSource(
            identifier: WeatherMapView.cellConeSourceID, features: features.cones, options: nil)
        let footprintSource = MLNShapeSource(
            identifier: WeatherMapView.cellFootprintSourceID, features: features.footprints, options: nil)
        let trackSource = MLNShapeSource(
            identifier: WeatherMapView.cellTrackSourceID, features: features.tracks, options: nil)
        let tickSource = MLNShapeSource(
            identifier: WeatherMapView.cellTickSourceID, features: features.ticks, options: nil)
        let headSource = MLNShapeSource(
            identifier: WeatherMapView.cellHeadSourceID, features: features.heads, options: nil)
        let pointSource = MLNShapeSource(
            identifier: WeatherMapView.cellPointSourceID, features: features.points, options: nil)
        for source in [coneSource, footprintSource, trackSource, tickSource, headSource, pointSource] {
            style.addSource(source)
        }

        // Peak-intensity steps aligned with the radar palette's hue progression
        // (mirrored in StormCellLegend). Typed constructors — see severityColor.
        let intensityColor = NSExpression(
            forMLNStepping: NSExpression(forKeyPath: "peak_mmh"),
            from: NSExpression(forConstantValue: UIColor(red: 0, green: 0.79, blue: 0.79, alpha: 1)),  // #00caca
            stops: NSExpression(forConstantValue: [
                2: UIColor(red: 1, green: 1, blue: 0, alpha: 1),          // moderate: #ffff00
                10: UIColor(red: 1, green: 0, blue: 0, alpha: 1),         // heavy: #ff0000
                50: UIColor(red: 0.996, green: 0.2, blue: 1, alpha: 1),   // extreme: #fe33ff
            ])
        )

        // Uncertainty cone: a faint wash widening along the track (hurricane-cone
        // visual language) — beneath everything else.
        let cone = MLNFillStyleLayer(identifier: WeatherMapView.cellConeLayerID, source: coneSource)
        cone.fillColor = NSExpression(forConstantValue: UIColor.white)
        cone.fillOpacity = NSExpression(forConstantValue: 0.08)
        insertOverlayLayer(cone, in: style)

        // Actual echo footprint, tinted by peak intensity.
        let footprintFill = MLNFillStyleLayer(
            identifier: WeatherMapView.cellFootprintFillLayerID, source: footprintSource)
        footprintFill.fillColor = intensityColor
        footprintFill.fillOpacity = NSExpression(forConstantValue: 0.14)
        insertOverlayLayer(footprintFill, in: style)

        let footprintLine = MLNLineStyleLayer(
            identifier: WeatherMapView.cellFootprintLineLayerID, source: footprintSource)
        footprintLine.lineColor = intensityColor
        footprintLine.lineOpacity = NSExpression(forConstantValue: 0.8)
        footprintLine.lineWidth = NSExpression(forConstantValue: 1.3)
        insertOverlayLayer(footprintLine, in: style)

        let track = MLNLineStyleLayer(identifier: WeatherMapView.cellTrackLayerID, source: trackSource)
        track.lineColor = NSExpression(forConstantValue: UIColor.white)
        track.lineOpacity = NSExpression(forConstantValue: 0.75)
        track.lineWidth = NSExpression(forConstantValue: 1.8)
        track.lineDashPattern = NSExpression(forConstantValue: [1.8, 1.6])
        track.lineCap = NSExpression(forConstantValue: "round")
        insertOverlayLayer(track, in: style)

        // +15-min tick dots along the track.
        let ticks = MLNCircleStyleLayer(identifier: WeatherMapView.cellTickLayerID, source: tickSource)
        ticks.circleColor = NSExpression(forConstantValue: UIColor.white)
        ticks.circleRadius = NSExpression(forConstantValue: 2.4)
        ticks.circleOpacity = NSExpression(forConstantValue: 0.95)
        ticks.circleStrokeColor = NSExpression(forConstantValue: UIColor.black)
        ticks.circleStrokeWidth = NSExpression(forConstantValue: 0.75)
        ticks.circleStrokeOpacity = NSExpression(forConstantValue: 0.25)
        insertOverlayLayer(ticks, in: style)

        let circles = MLNCircleStyleLayer(identifier: WeatherMapView.cellCircleLayerID, source: pointSource)
        circles.circleColor = intensityColor
        circles.circleRadius = NSExpression(
            forMLNStepping: NSExpression(forKeyPath: "area_km2"),
            from: NSExpression(forConstantValue: 4.5),
            stops: NSExpression(forConstantValue: [80: 6, 300: 7.5])
        )
        circles.circleOpacity = NSExpression(forConstantValue: 0.9)
        circles.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
        circles.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
        insertOverlayLayer(circles, in: style)

        // Arrowhead + tick labels read ABOVE the map labels, like the motion arrows.
        if style.image(forName: WeatherMapView.cellArrowImageName) == nil {
            style.setImage(RadarArrowGeometry.arrowImage(), forName: WeatherMapView.cellArrowImageName)
        }
        let heads = MLNSymbolStyleLayer(identifier: WeatherMapView.cellHeadLayerID, source: headSource)
        heads.iconImageName = NSExpression(forConstantValue: WeatherMapView.cellArrowImageName)
        heads.iconRotation = NSExpression(forKeyPath: "rotation")
        heads.iconScale = NSExpression(forConstantValue: 0.7)
        heads.iconRotationAlignment = NSExpression(forConstantValue: "map")
        heads.iconAllowsOverlap = NSExpression(forConstantValue: true)
        heads.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        heads.iconOpacity = NSExpression(forConstantValue: 0.9)
        style.addLayer(heads)

        let tickLabels = MLNSymbolStyleLayer(
            identifier: WeatherMapView.cellTickLabelLayerID, source: tickSource)
        tickLabels.text = NSExpression(forKeyPath: "label")
        // The ONLY font stack the OpenFreeMap styles serve glyphs for.
        tickLabels.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
        tickLabels.textFontSize = NSExpression(forConstantValue: 10)
        tickLabels.textColor = NSExpression(forConstantValue: UIColor.white)
        tickLabels.textHaloColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.55))
        tickLabels.textHaloWidth = NSExpression(forConstantValue: 1)
        tickLabels.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: -1.1)))
        tickLabels.textAllowsOverlap = NSExpression(forConstantValue: false)
        style.addLayer(tickLabels)
    }

    private func removeStormCellLayers(from style: MLNStyle) {
        for id in [WeatherMapView.cellHeadLayerID, WeatherMapView.cellTickLabelLayerID,
                   WeatherMapView.cellCircleLayerID, WeatherMapView.cellTickLayerID,
                   WeatherMapView.cellTrackLayerID, WeatherMapView.cellFootprintLineLayerID,
                   WeatherMapView.cellFootprintFillLayerID, WeatherMapView.cellConeLayerID] {
            if let layer = style.layer(withIdentifier: id) { style.removeLayer(layer) }
        }
        for id in [WeatherMapView.cellPointSourceID, WeatherMapView.cellTrackSourceID,
                   WeatherMapView.cellConeSourceID, WeatherMapView.cellFootprintSourceID,
                   WeatherMapView.cellTickSourceID, WeatherMapView.cellHeadSourceID] {
            if let source = style.source(withIdentifier: id) { style.removeSource(source) }
        }
    }

    private static func parseStormCells(
        _ collection: Components.Schemas.StormCellCollection
    ) -> [StormCellInfo] {
        collection.features.compactMap { feature in
            guard feature.geometry.coordinates.count == 2 else { return nil }
            func coordinate(_ pair: [Double]) -> CLLocationCoordinate2D? {
                pair.count == 2
                    ? CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0]) : nil
            }
            return StormCellInfo(
                id: feature.properties.id,
                center: CLLocationCoordinate2D(
                    latitude: feature.geometry.coordinates[1],
                    longitude: feature.geometry.coordinates[0]),
                areaKm2: feature.properties.area_km2,
                peakMmh: feature.properties.peak_mmh,
                meanMmh: feature.properties.mean_mmh ?? feature.properties.peak_mmh,
                velocityKmh: feature.properties.velocity_kmh,
                bearingDeg: feature.properties.bearing_deg ?? 0,
                path: feature.properties.path.compactMap(coordinate),
                footprint: (feature.properties.footprint ?? []).compactMap(coordinate))
        }
    }

    private struct StormCellFeatureSet {
        var points: [MLNPointFeature] = []
        var tracks: [MLNPolylineFeature] = []
        var cones: [MLNPolygonFeature] = []
        var footprints: [MLNPolygonFeature] = []
        var ticks: [MLNPointFeature] = []
        var heads: [MLNPointFeature] = []
    }

    /// Rebuilds the overlay geometry from the parsed cells: marker points, track
    /// polylines with +15-min ticks and an end arrowhead, footprint hull polygons
    /// and the widening uncertainty cone (half-width = footprint radius growing
    /// ~18% of the distance traveled — honest about extrapolation error).
    private static func buildStormCellFeatures(_ cells: [StormCellInfo]) -> StormCellFeatureSet {
        var set = StormCellFeatureSet()
        for cell in cells {
            let point = MLNPointFeature()
            point.coordinate = cell.center
            point.attributes = [
                "cell_id": cell.id,
                "peak_mmh": cell.peakMmh,
                "area_km2": cell.areaKm2,
            ]
            set.points.append(point)

            if cell.footprint.count >= 4 {
                var ring = cell.footprint
                let footprint = MLNPolygonFeature(
                    coordinates: &ring, count: UInt(ring.count), interiorPolygons: nil)
                footprint.attributes = ["cell_id": cell.id, "peak_mmh": cell.peakMmh]
                set.footprints.append(footprint)
            }

            // Track features only for cells that actually move — a stationary
            // cell's "track" would be a dot pile with a random arrowhead.
            var trackPoints = [cell.center] + cell.path
            guard cell.velocityKmh >= 3, trackPoints.count >= 2 else { continue }

            let track = MLNPolylineFeature(
                coordinates: &trackPoints, count: UInt(trackPoints.count))
            set.tracks.append(track)

            for (index, position) in cell.path.enumerated() {
                let tick = MLNPointFeature()
                tick.coordinate = position
                let minutes = 15 * (index + 1)
                // Label only +30/+60 — every tick labeled reads as clutter.
                // ASCII apostrophe: the OpenFreeMap glyph ranges may not carry U+2032.
                tick.attributes = ["label": minutes % 30 == 0 ? "+\(minutes)'" : ""]
                set.ticks.append(tick)
            }

            let last = trackPoints[trackPoints.count - 1]
            let previous = trackPoints[trackPoints.count - 2]
            let direction = kmVector(from: previous, to: last)
            let head = MLNPointFeature()
            head.coordinate = last
            head.attributes = [
                "rotation": atan2(direction.x, direction.y) * 180 / .pi,
            ]
            set.heads.append(head)

            if let cone = conePolygon(for: cell, trackPoints: trackPoints) {
                set.cones.append(cone)
            }
        }
        return set
    }

    /// Uncertainty cone around the projected track: left/right offsets whose
    /// half-width starts at the footprint radius and grows with distance.
    private static func conePolygon(
        for cell: StormCellInfo, trackPoints: [CLLocationCoordinate2D]
    ) -> MLNPolygonFeature? {
        let baseWidth = max(2.0, cell.radiusKm)
        var left: [CLLocationCoordinate2D] = []
        var right: [CLLocationCoordinate2D] = []
        var traveled = 0.0
        for index in trackPoints.indices {
            let incoming = index > 0
                ? kmVector(from: trackPoints[index - 1], to: trackPoints[index])
                : kmVector(from: trackPoints[0], to: trackPoints[1])
            let outgoing = index < trackPoints.count - 1
                ? kmVector(from: trackPoints[index], to: trackPoints[index + 1])
                : incoming
            if index > 0 { traveled += (incoming.x * incoming.x + incoming.y * incoming.y).squareRoot() }
            // Averaged direction at interior vertices keeps the cone smooth.
            let dx = incoming.x + outgoing.x, dy = incoming.y + outgoing.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0.01 else { return nil }
            let normal = (x: -dy / length, y: dx / length)
            let halfWidth = baseWidth + 0.18 * traveled
            left.append(offset(trackPoints[index], eastKm: normal.x * halfWidth,
                               northKm: normal.y * halfWidth))
            right.append(offset(trackPoints[index], eastKm: -normal.x * halfWidth,
                                northKm: -normal.y * halfWidth))
        }
        guard traveled >= baseWidth else { return nil }   // barely moves → no cone
        var ring = left + right.reversed()
        ring.append(ring[0])
        return MLNPolygonFeature(coordinates: &ring, count: UInt(ring.count), interiorPolygons: nil)
    }

    /// Local flat-earth kilometers from `a` to `b` (fine at storm-track scale).
    private static func kmVector(
        from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D
    ) -> (x: Double, y: Double) {
        let midLat = (a.latitude + b.latitude) / 2 * .pi / 180
        return ((b.longitude - a.longitude) * 111.320 * cos(midLat),
                (b.latitude - a.latitude) * 110.574)
    }

    private static func offset(
        _ base: CLLocationCoordinate2D, eastKm: Double, northKm: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: base.latitude + northKm / 110.574,
            longitude: base.longitude + eastKm
                / (111.320 * max(0.2, cos(base.latitude * .pi / 180))))
    }
}
