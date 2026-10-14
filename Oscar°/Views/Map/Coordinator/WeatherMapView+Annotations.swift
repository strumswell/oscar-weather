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

    func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
        guard annotation is MLNUserLocation else { return nil }
        return MLNUserLocationAnnotationView(reuseIdentifier: "user-location-hidden")
    }

    // MARK: User location dot (style layers)

    func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
        guard let style = mapView.style else { return }
        syncUserLocationDot(style: style)
    }

    func syncUserLocationDot(style: MLNStyle) {
        guard !isTornDown else { return }
        UserLocationDot.sync(style: style, coordinate: mapView?.userLocation?.coordinate)

        let wantsPulse = !UIAccessibility.isReduceMotionEnabled
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
