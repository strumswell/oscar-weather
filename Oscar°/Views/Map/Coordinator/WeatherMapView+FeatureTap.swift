import CoreLocation
import MapLibre
import Metal
import OSLog
import Observation
import SwiftUI
import UIKit

// MARK: Feature tap-through (warnings + storm cells)

extension WeatherMapView.Coordinator {
    /// Query the tapped point's rendered features: cells win (small targets, padded
    /// hit box), then every warning polygon under the finger — deduped by alert id
    /// (MultiPolygon parts return one feature each) and sorted active-first.
    @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let mapView else { return }
        let point = gesture.location(in: mapView)

        let pad: CGFloat = 22
        let hitBox = CGRect(x: point.x - pad, y: point.y - pad, width: pad * 2, height: pad * 2)
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

        guard parent.onAlertsTapped != nil else { return }
        let warningFeatures = mapView.visibleFeatures(
            at: point, styleLayerIdentifiers: WeatherMapView.alertFillLayerIDs)
        guard !warningFeatures.isEmpty else { return }
        Haptics.impact()

        // The dissolved overlay features carry no per-alert text, so the tap
        // resolves against `/weather-alerts/point` at the tapped coordinate —
        // exact geometry containment, full official texts. If the fetch fails,
        // fall back to whatever the rendered attributes carry (per-alert
        // features from an older server still work fully offline-cached).
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
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
}
