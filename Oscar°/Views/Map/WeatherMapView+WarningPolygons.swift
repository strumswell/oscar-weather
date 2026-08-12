import CoreLocation
import MapLibre
import Metal
import OSLog
import Observation
import SwiftUI
import UIKit

// MARK: Severe-weather warning polygons

extension WeatherMapView.Coordinator {
    struct AlertFetchBox {
        let minLat: Double
        let maxLat: Double
        let minLon: Double
        let maxLon: Double
    }

    /// The map's visible bounds as a box; falls back to a viewport-sized window
    /// around the given center before the map has laid out.
    private func visibleAlertBox(fallbackCenter: CLLocationCoordinate2D) -> AlertFetchBox {
        if let bounds = mapView?.visibleCoordinateBounds,
           bounds.ne.latitude > bounds.sw.latitude {
            return AlertFetchBox(
                minLat: bounds.sw.latitude, maxLat: bounds.ne.latitude,
                minLon: bounds.sw.longitude, maxLon: bounds.ne.longitude
            )
        }
        return AlertFetchBox(
            minLat: fallbackCenter.latitude - 5, maxLat: fallbackCenter.latitude + 5,
            minLon: fallbackCenter.longitude - 7, maxLon: fallbackCenter.longitude + 7
        )
    }

    /// Visible bounds + 50% pan/zoom headroom per side, clamped to the server's
    /// 25°×40° `/area` guard and world bounds.
    private func alertRequestBox(visible: AlertFetchBox) -> AlertFetchBox {
        let latPad = (visible.maxLat - visible.minLat) * 0.5
        let lonPad = (visible.maxLon - visible.minLon) * 0.5
        return clampedToAreaGuard(AlertFetchBox(
            minLat: visible.minLat - latPad, maxLat: visible.maxLat + latPad,
            minLon: visible.minLon - lonPad, maxLon: visible.maxLon + lonPad
        ))
    }

    /// Shrinks a box to the server's `/area` span guard (kept centered) and clamps
    /// it to world bounds. Also applied to the *visible* box in the outgrown check:
    /// a whole-continent viewport can never be contained by any fetchable box, and
    /// comparing the clamped (= servable) part prevents a refetch-every-sync loop.
    private func clampedToAreaGuard(_ box: AlertFetchBox) -> AlertFetchBox {
        let maxLatSpan = 24.0
        let maxLonSpan = 38.0
        var minLat = box.minLat
        var maxLat = box.maxLat
        var minLon = box.minLon
        var maxLon = box.maxLon
        if maxLat - minLat > maxLatSpan {
            let center = (minLat + maxLat) / 2
            minLat = center - maxLatSpan / 2
            maxLat = center + maxLatSpan / 2
        }
        if maxLon - minLon > maxLonSpan {
            let center = (minLon + maxLon) / 2
            minLon = center - maxLonSpan / 2
            maxLon = center + maxLonSpan / 2
        }
        return AlertFetchBox(
            minLat: max(-89.9, minLat), maxLat: min(89.9, maxLat),
            minLon: max(-179.9, minLon), maxLon: min(179.9, maxLon)
        )
    }

    private func alertBoxContains(_ outer: AlertFetchBox, _ inner: AlertFetchBox) -> Bool {
        inner.minLat >= outer.minLat && inner.maxLat <= outer.maxLat
            && inner.minLon >= outer.minLon && inner.maxLon <= outer.maxLon
    }

    /// Warning areas draw ON TOP of whichever radar/model layer is active —
    /// translucent severity-colored fills plus a crisp outline, refreshed at
    /// most every 5 minutes while the toggle is on.
    func syncAlertPolygons(style: MLNStyle, active: Bool) {
        guard active else {
            removeAlertPolygonLayers(from: style)
            return
        }

        let center = mapView?.centerCoordinate ?? parent.coordinates
        let visible = visibleAlertBox(fallbackCenter: center)
        let request = alertRequestBox(visible: visible)
        let isStale = alertOverlayFetchedAt.map { Date().timeIntervalSince($0) > 300 } ?? true
        // The fetch box is the visible bounds plus pan/zoom headroom, so a refetch
        // is needed whenever the viewport outgrows the last fetched box (long pan
        // OR zoom-out) — otherwise warnings would silently stop at the box edge.
        let outgrown = alertOverlayBox.map { !alertBoxContains($0, clampedToAreaGuard(visible)) } ?? true
        if (isStale || outgrown), !isLoadingAlertOverlay {
            isLoadingAlertOverlay = true
            Task { @MainActor [weak self] in
                defer { self?.isLoadingAlertOverlay = false }
                do {
                    let data = try await APIClient.shared.getWeatherAlertPolygons(
                        minLat: request.minLat, maxLat: request.maxLat,
                        minLon: request.minLon, maxLon: request.maxLon
                    )
                    guard let self, !self.isTornDown else { return }
                    self.alertOverlayData = data
                    self.alertOverlayFetchedAt = Date()
                    self.alertOverlayBox = request
                    // Swap the shapes into the existing sources instead of tearing
                    // them down: MapLibre re-tiles a fresh GeoJSON source
                    // asynchronously, so a rebuild blanks the polygons for a beat on
                    // every refresh (the isobar sources use the same pattern).
                    if let style = self.mapView?.style,
                       style.source(withIdentifier: WeatherMapView.alertSourceID(0)) != nil,
                       let chunks = Self.alertShapeChunks(data: data) {
                        for (index, chunk) in chunks.enumerated() {
                            (style.source(withIdentifier: WeatherMapView.alertSourceID(index)) as? MLNShapeSource)?
                                .shape = chunk
                        }
                    } else {
                        self.syncAll()
                    }
                } catch {
                    weatherMapLogger.error("Alert polygon fetch failed: \(error.localizedDescription, privacy: .public)")
                    // Back off until the staleness window elapses; keep stale data
                    // visible and stop outgrown-retriggering for the attempted box.
                    self?.alertOverlayFetchedAt = Date()
                    self?.alertOverlayBox = request
                }
            }
        }

        guard style.source(withIdentifier: WeatherMapView.alertSourceID(0)) == nil else { return }
        guard let data = alertOverlayData,
              let chunks = Self.alertShapeChunks(data: data)
        else { return }

        // Severity ranks: 1 Minor (default), 2 Moderate, 3 Severe, 4 Extreme.
        // Typed constructor — MapLibre's NSExpression parser rejects the old
        // MGL_MATCH format-string spelling at runtime. Meteoalarm's ladder has
        // no Minor (yellow IS Moderate), so its shapes color one step lighter
        // to match the national services' own maps; mirrors
        // `AlertSeverityStyle.color(rank:source:)`.
        let meteoalarmColor = NSExpression(
            forMLNMatchingKey: NSExpression(forKeyPath: "severity_rank"),
            in: [
                NSExpression(forConstantValue: 3): NSExpression(forConstantValue: UIColor.systemOrange),
                NSExpression(forConstantValue: 4): NSExpression(forConstantValue: UIColor.systemRed),
            ],
            default: NSExpression(forConstantValue: UIColor.systemYellow)
        )
        let nativeColor = NSExpression(
            forMLNMatchingKey: NSExpression(forKeyPath: "severity_rank"),
            in: [
                NSExpression(forConstantValue: 2): NSExpression(forConstantValue: UIColor.systemOrange),
                NSExpression(forConstantValue: 3): NSExpression(forConstantValue: UIColor.systemRed),
                NSExpression(forConstantValue: 4): NSExpression(forConstantValue: UIColor.systemPurple),
            ],
            default: NSExpression(forConstantValue: UIColor.systemYellow)
        )
        let severityColor = NSExpression(
            forMLNMatchingKey: NSExpression(forKeyPath: "source"),
            in: [NSExpression(forConstantValue: "meteoalarm"): meteoalarmColor],
            default: nativeColor
        )
        for (index, chunk) in chunks.enumerated() {
            let source = MLNShapeSource(
                identifier: WeatherMapView.alertSourceID(index), shape: chunk, options: nil)
            style.addSource(source)

            let fill = MLNFillStyleLayer(
                identifier: WeatherMapView.alertFillLayerID(index), source: source)
            fill.fillColor = severityColor
            fill.fillOpacity = NSExpression(forConstantValue: 0.16)
            insertOverlayLayer(fill, in: style)

            let outline = MLNLineStyleLayer(
                identifier: WeatherMapView.alertOutlineLayerID(index), source: source)
            outline.lineColor = severityColor
            outline.lineWidth = NSExpression(forConstantValue: 1.6)
            // Outlines only from regional zoom in: Meteoalarm neighbors
            // genuinely neither touch nor share borders (thin gap strips
            // between French departments), so at country scale the doubled
            // border lines collapse into scribble artifacts — there the
            // fills alone carry the severity, like DWD's own warning map.
            outline.lineOpacity = NSExpression(
                forMLNInterpolating: NSExpression(forVariable: "zoomLevel"),
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [6.2: 0, 7.2: 0.9])
            )
            // Round joins: the default miter shoots needle spikes off acute
            // vertices in the server's viewport-decimated rings.
            outline.lineJoin = NSExpression(forConstantValue: "round")
            outline.lineCap = NSExpression(forConstantValue: "round")
            insertOverlayLayer(outline, in: style)
        }
    }

    /// The fetched FeatureCollection distributed round-robin into
    /// `alertSourceCount` chunks (see the source-ID comment). Always returns
    /// exactly that many shapes; a non-collection payload lands in chunk 0.
    private static func alertShapeChunks(data: Data) -> [MLNShape]? {
        guard let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue)
        else { return nil }
        guard let collection = shape as? MLNShapeCollectionFeature else {
            return [shape] + (1..<WeatherMapView.alertSourceCount).map { _ in
                MLNShapeCollectionFeature(shapes: [])
            }
        }
        var buckets: [[MLNShape & MLNFeature]] = Array(
            repeating: [], count: WeatherMapView.alertSourceCount)
        for (index, feature) in collection.shapes.enumerated() {
            buckets[index % WeatherMapView.alertSourceCount].append(feature)
        }
        return buckets.map { MLNShapeCollectionFeature(shapes: $0) }
    }


    private func removeAlertPolygonLayers(from style: MLNStyle) {
        for index in 0..<WeatherMapView.alertSourceCount {
            if let layer = style.layer(withIdentifier: WeatherMapView.alertFillLayerID(index)) {
                style.removeLayer(layer)
            }
            if let layer = style.layer(withIdentifier: WeatherMapView.alertOutlineLayerID(index)) {
                style.removeLayer(layer)
            }
            if let source = style.source(withIdentifier: WeatherMapView.alertSourceID(index)) {
                style.removeSource(source)
            }
        }
    }
}
