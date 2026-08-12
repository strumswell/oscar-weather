import CoreLocation
import MapLibre
import Metal
import OSLog
import Observation
import SwiftUI
import UIKit

// MARK: Annotations, user location dot, selected-city marker

extension WeatherMapView.Coordinator {
    // MARK: Annotations

    nonisolated func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
        nonisolated(unsafe) var result: MLNAnnotationView?
        nonisolated(unsafe) let annotation = annotation
        MainActor.assumeIsolated {
            guard annotation is MLNUserLocation else { return }
            // Empty view suppresses the stock puck: view-based annotations lag
            // one display frame behind the basemap during gestures. The visible
            // dot renders in-style instead (UserLocationDot, syncUserLocationDot).
            result = MLNUserLocationAnnotationView(reuseIdentifier: "user-location-hidden")
        }
        return result
    }

    // MARK: User location dot (style layers)

    nonisolated func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
        MainActor.assumeIsolated {
            guard let style = mapView.style else { return }
            syncUserLocationDot(style: style)
        }
    }

    func syncUserLocationDot(style: MLNStyle) {
        UserLocationDot.sync(style: style, coordinate: mapView?.userLocation?.coordinate)

        // Pulse only on the fullscreen map: each beat animates paint
        // transitions, which keeps the map render loop busy — too costly for
        // the always-on NowView preview card.
        let wantsPulse = parent.userActionAllowed && !UIAccessibility.isReduceMotionEnabled
        if wantsPulse, userDotPulseTimer == nil {
            userDotPulseTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.isTornDown, let style = self.mapView?.style else { return }
                    UserLocationDot.pulseBeat(style: style)
                }
            }
        } else if !wantsPulse {
            userDotPulseTimer?.invalidate()
            userDotPulseTimer = nil
        }
    }

    // MARK: Selected-city marker (style layer)

    /// iOS-style marker replica for the selected city (red balloon, white
    /// location glyph, tip anchored on the spot) as a style symbol layer.
    /// The former MLNPointAnnotation rendered in MapLibre's internal
    /// annotation layer, which sat BELOW later-added overlay layers — the
    /// marker vanished under radar and warning fills. As a style layer it
    /// re-hoists itself topmost like the chips and the user dot.
    private static let cityMarkerSourceID = "oscar-selected-city"
    private static let cityMarkerLayerID = "oscar-selected-city-layer"
    private static let cityMarkerImageName = "oscar-selected-city-marker"

    func syncSelectedCityMarker(style: MLNStyle) {
        let selectedCity = parent.cities.first(where: \.selected)

        guard let selectedCity else {
            if selectedCityMarkerIdentity != nil {
                if let layer = style.layer(withIdentifier: Self.cityMarkerLayerID) {
                    style.removeLayer(layer)
                }
                if let source = style.source(withIdentifier: Self.cityMarkerSourceID) {
                    style.removeSource(source)
                }
                selectedCityMarkerIdentity = nil
            }
            return
        }

        let point = MLNPointAnnotation()
        point.coordinate = CLLocationCoordinate2D(
            latitude: selectedCity.lat, longitude: selectedCity.lon)

        if let source = style.source(withIdentifier: Self.cityMarkerSourceID) as? MLNShapeSource {
            let identity = "\(selectedCity.lat)|\(selectedCity.lon)"
            if selectedCityMarkerIdentity != identity {
                source.shape = point
                selectedCityMarkerIdentity = identity
            }
        } else {
            // The marker canvas is twice the balloon-tip's y, so the default
            // center icon anchor pins the tip on the coordinate.
            style.setImage(CityMarkerImage.make(), forName: Self.cityMarkerImageName)
            let source = MLNShapeSource(identifier: Self.cityMarkerSourceID,
                                        shape: point, options: nil)
            style.addSource(source)
            let layer = MLNSymbolStyleLayer(identifier: Self.cityMarkerLayerID, source: source)
            layer.iconImageName = NSExpression(forConstantValue: Self.cityMarkerImageName)
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(layer)
            selectedCityMarkerIdentity = "\(selectedCity.lat)|\(selectedCity.lon)"
        }

        if style.layers.last?.identifier != Self.cityMarkerLayerID,
           let layer = style.layer(withIdentifier: Self.cityMarkerLayerID) {
            style.removeLayer(layer)
            style.addLayer(layer)
        }
    }
}
