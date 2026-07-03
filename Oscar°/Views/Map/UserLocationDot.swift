//
//  UserLocationDot.swift
//  Oscar°
//
//  iOS-style user-location dot, rendered as STYLE layers instead of the stock
//  annotation view.
//

import CoreLocation
import MapLibre
import UIKit

/// The blue location dot as circle layers inside the map style. View-based
/// annotations (incl. every `MLNUserLocationAnnotationView`) are repositioned in
/// UIKit after each rendered map frame and composite one display frame behind the
/// Metal basemap — the dot visibly swims against the map during pans. Style layers
/// render inside the map's own frame, locked to the basemap by construction (the
/// selected-city marker is an annotation IMAGE and never swam for the same reason).
///
/// The dot idles with a soft static halo; the fullscreen map additionally pulses
/// via `pulseBeat` (paint-property transitions) — a beat forces the map to render
/// while it animates, so the always-on NowView preview deliberately stays static.
@MainActor
enum UserLocationDot {
    static let sourceID = "oscar-user-location"
    static let haloLayerID = "oscar-user-location-halo"
    static let pulseLayerID = "oscar-user-location-pulse"
    static let dotLayerID = "oscar-user-location-dot"

    private static let dotRadius: Double = 5
    private static let ringWidth: Double = 3
    private static let haloRadius: Double = 12
    private static let pulseMaxRadius: Double = 18

    /// Creates the source + layers on first call, then just moves the point.
    /// Re-appends the layers whenever something else (arrows, value bubbles, a
    /// fresh overlay layer) landed above them — the dot always reads topmost.
    static func sync(style: MLNStyle, coordinate: CLLocationCoordinate2D?) {
        var shape: MLNShape?
        if let coordinate, CLLocationCoordinate2DIsValid(coordinate),
           coordinate.latitude != 0 || coordinate.longitude != 0 {
            let point = MLNPointAnnotation()
            point.coordinate = coordinate
            shape = point
        }

        if let source = style.source(withIdentifier: sourceID) as? MLNShapeSource {
            source.shape = shape
        } else {
            let source = MLNShapeSource(identifier: sourceID, shape: shape, options: nil)
            style.addSource(source)

            let halo = MLNCircleStyleLayer(identifier: haloLayerID, source: source)
            halo.circleColor = NSExpression(forConstantValue: UIColor.systemBlue)
            halo.circleRadius = NSExpression(forConstantValue: haloRadius)
            halo.circleOpacity = NSExpression(forConstantValue: 0.15)
            style.addLayer(halo)

            let pulse = MLNCircleStyleLayer(identifier: pulseLayerID, source: source)
            pulse.circleColor = NSExpression(forConstantValue: UIColor.systemBlue)
            pulse.circleRadius = NSExpression(forConstantValue: dotRadius + ringWidth)
            pulse.circleOpacity = NSExpression(forConstantValue: 0)
            style.addLayer(pulse)

            let dot = MLNCircleStyleLayer(identifier: dotLayerID, source: source)
            dot.circleColor = NSExpression(forConstantValue: UIColor.systemBlue)
            dot.circleRadius = NSExpression(forConstantValue: dotRadius)
            dot.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            dot.circleStrokeWidth = NSExpression(forConstantValue: ringWidth)
            style.addLayer(dot)
        }

        if style.layers.last?.identifier != dotLayerID {
            for id in [haloLayerID, pulseLayerID, dotLayerID] {
                if let layer = style.layer(withIdentifier: id) {
                    style.removeLayer(layer)
                    style.addLayer(layer)
                }
            }
        }
    }

    /// One pulse beat: snap the ring back to the dot rim, then expand + fade it
    /// out over an animated paint transition.
    static func pulseBeat(style: MLNStyle) {
        guard let pulse = style.layer(withIdentifier: pulseLayerID) as? MLNCircleStyleLayer else { return }
        let instant = MLNTransition(duration: 0, delay: 0)
        pulse.circleRadiusTransition = instant
        pulse.circleOpacityTransition = instant
        pulse.circleRadius = NSExpression(forConstantValue: dotRadius + ringWidth)
        pulse.circleOpacity = NSExpression(forConstantValue: 0.35)
        DispatchQueue.main.async {
            let eased = MLNTransition(duration: 1.6, delay: 0)
            pulse.circleRadiusTransition = eased
            pulse.circleOpacityTransition = eased
            pulse.circleRadius = NSExpression(forConstantValue: pulseMaxRadius)
            pulse.circleOpacity = NSExpression(forConstantValue: 0)
        }
    }
}
