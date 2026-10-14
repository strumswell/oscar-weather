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
