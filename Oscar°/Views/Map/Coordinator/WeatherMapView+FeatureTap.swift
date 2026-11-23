import CoreLocation
import MapLibre
import Metal
import OSLog
import Observation
import SwiftUI
import UIKit

// MARK: Feature tap-through (webcams, warnings, storm cells)

extension WeatherMapView.Coordinator {
    @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let mapView else { return }
        let point = gesture.location(in: mapView)

        let pad: CGFloat = 22
        let hitBox = CGRect(x: point.x - pad, y: point.y - pad, width: pad * 2, height: pad * 2)
        let webcamHit = mapView
            .visibleFeatures(in: hitBox, styleLayerIdentifiers: [WeatherMapView.webcamLayerID])
            .compactMap { feature in webcams.first { $0.id == feature.attributes["webcam_id"] as? Int } }
            .first
        if let webcamHit, let onWebcamTapped = parent.onWebcamTapped {
            Haptics.impact()
            onWebcamTapped(webcamHit)
            return
        }
        let cellHit = mapView
            .visibleFeatures(in: hitBox, styleLayerIdentifiers: [
                WeatherMapView.cellCircleLayerID, WeatherMapView.cellFootprintFillLayerID,
            ])
            .compactMap { feature -> StormCellInfo? in
                guard let id = feature.attributes["cell_id"] as? Int else { return nil }
                return stormCells?.first { $0.id == id }
            }
            .first
        if let cellHit, let onCellTapped = parent.onCellTapped {
            Haptics.impact()
            onCellTapped(cellHit)
            return
        }

        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        let warningFeatures = parent.onAlertsTapped == nil ? [] : mapView.visibleFeatures(
            at: point, styleLayerIdentifiers: WeatherMapView.alertFillLayerIDs)
        guard !warningFeatures.isEmpty else {
            precipTapped(at: coordinate)
            return
        }
        Haptics.impact()

        var seen = Set<String>()
        var attributeAlerts: [WeatherAlertInfo] = []
        for feature in warningFeatures {
            guard let info = WeatherAlertInfo(attributes: feature.attributes),
                  seen.insert(info.id).inserted else { continue }
            attributeAlerts.append(info)
        }
        Task { @MainActor [weak self] in
            guard let self, let onAlertsTapped = self.parent.onAlertsTapped else { return }
            var alerts: [WeatherAlertInfo] = []
            do {
                alerts = try await APIClient.shared.getOscarPointAlerts(coordinates: coordinate)
                    .alerts.map(WeatherAlertInfo.init(pointAlert:))
            } catch {
                weatherMapLogger.warning("point alerts failed: \(error.localizedDescription, privacy: .public)")
            }
            if alerts.isEmpty {
                alerts = attributeAlerts
            }
            guard !alerts.isEmpty else { return }
            alerts = alerts.sortedForDisplay()
            onAlertsTapped(alerts)
        }
    }

    private func precipTapped(at coordinate: CLLocationCoordinate2D) {
        let radarActive = parent.layerOverride?.radar ?? parent.settingsService.oscarRadarLayer
        guard radarActive, parent.combinedTimeline?.isShowingModel != true,
              let state = parent.oscarRadarState, parent.onPrecipTapped != nil else { return }
        Task { @MainActor [weak self] in
            guard let tap = await state.precipTap(at: coordinate),
                  let onPrecipTapped = self?.parent.onPrecipTapped else { return }
            Haptics.impact()
            onPrecipTapped(tap)
        }
    }

    func syncPrecipRing(style: MLNStyle) {
        guard let coordinate = parent.precipRing else {
            style.removeLayers(withIdentifiers: [WeatherMapView.precipRingLayerID, WeatherMapView.precipRingHaloLayerID])
            style.removeSources(withIdentifiers: [WeatherMapView.precipRingSourceID])
            precipRingCoordinate = nil
            return
        }
        let point = MLNPointFeature()
        point.coordinate = coordinate
        if let source = style.source(withIdentifier: WeatherMapView.precipRingSourceID) as? MLNShapeSource {
            if precipRingCoordinate?.latitude != coordinate.latitude
                || precipRingCoordinate?.longitude != coordinate.longitude {
                source.shape = point
            }
        } else {
            let source = MLNShapeSource(identifier: WeatherMapView.precipRingSourceID, shape: point)
            style.addSource(source)
            let halo = MLNCircleStyleLayer(identifier: WeatherMapView.precipRingHaloLayerID, source: source)
            halo.circleRadius = NSExpression(forConstantValue: 7.5)
            halo.circleOpacity = NSExpression(forConstantValue: 0)
            halo.circleStrokeWidth = NSExpression(forConstantValue: 3.5)
            halo.circleStrokeColor = NSExpression(forConstantValue: UIColor(red: 0.04, green: 0.08, blue: 0.16, alpha: 1))
            halo.circleStrokeOpacity = NSExpression(forConstantValue: 0.5)
            insertOverlayLayer(halo, in: style)
            let ring = MLNCircleStyleLayer(identifier: WeatherMapView.precipRingLayerID, source: source)
            ring.circleRadius = NSExpression(forConstantValue: 7.5)
            ring.circleOpacity = NSExpression(forConstantValue: 0)
            ring.circleStrokeWidth = NSExpression(forConstantValue: 2.5)
            ring.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            style.insertLayer(ring, above: halo)
        }
        precipRingCoordinate = coordinate
    }
}
