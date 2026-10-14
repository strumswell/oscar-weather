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

    private func alertRequestBox(visible: AlertFetchBox) -> AlertFetchBox {
        let latPad = (visible.maxLat - visible.minLat) * 0.5
        let lonPad = (visible.maxLon - visible.minLon) * 0.5
        return clampedToAreaGuard(AlertFetchBox(
            minLat: visible.minLat - latPad, maxLat: visible.maxLat + latPad,
            minLon: visible.minLon - lonPad, maxLon: visible.maxLon + lonPad
        ))
    }

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

    func syncAlertPolygons(style: MLNStyle, active: Bool) {
        guard active else {
            removeAlertPolygonLayers(from: style)
            return
        }

        let center = mapView?.centerCoordinate ?? parent.coordinates
        let visible = visibleAlertBox(fallbackCenter: center)
        let request = alertRequestBox(visible: visible)
        let isStale = alertOverlayFetchedAt.map { Date().timeIntervalSince($0) > 300 } ?? true
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
                    self?.alertOverlayFetchedAt = Date()
                    self?.alertOverlayBox = request
                }
            }
        }

        guard style.source(withIdentifier: WeatherMapView.alertSourceID(0)) == nil else { return }
        guard let data = alertOverlayData,
              let chunks = Self.alertShapeChunks(data: data)
        else { return }

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
            outline.lineOpacity = NSExpression(
                forMLNInterpolating: NSExpression(forVariable: "zoomLevel"),
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [6.2: 0, 7.2: 0.9])
            )
            outline.lineJoin = NSExpression(forConstantValue: "round")
            outline.lineCap = NSExpression(forConstantValue: "round")
            insertOverlayLayer(outline, in: style)
        }
    }

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
            style.removeLayers(withIdentifiers: [
                WeatherMapView.alertFillLayerID(index), WeatherMapView.alertOutlineLayerID(index),
            ])
            style.removeSources(withIdentifiers: [WeatherMapView.alertSourceID(index)])
        }
    }
}
