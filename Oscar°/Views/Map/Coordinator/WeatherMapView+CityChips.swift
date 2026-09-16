import CoreLocation
import MapLibre
import Metal
import OSLog
import Observation
import SwiftUI
import UIKit

// MARK: Saved-city chips (like the locations picker map)

extension WeatherMapView.Coordinator {
    private static let cityChipSourceID = "oscar-city-chips"
    private static let cityChipLayerID = "oscar-city-chips-layer"

    /// The picker map's city chips on the weather map: every saved city as
    /// a conditions capsule (condition symbol + temperature) with the
    /// identity line ("emoji label") underneath. The selected city keeps its
    /// red marker instead of a chip.
    func syncCityChips(style: MLNStyle) {
        // Read through the store so the observation loop re-fires this sync
        // the moment the batch conditions land.
        let store = CityConditionsStore.shared
        var features: [MLNPointFeature] = []
        var signature = ""
        for city in parent.cities where !city.selected {
            let coordinate = CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
            let customLabel = city.customLabel ?? ""
            // The custom emoji leads the identity line under the capsule,
            // not the capsule itself.
            let identityLine = [city.emoji ?? "", customLabel]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let iconName: String
            if let conditions = store.conditions(for: coordinate) {
                let temperatureText = "\(Int(conditions.temperature.rounded()))°"
                iconName = "oscar-city-chip-\(conditions.iconAssetName)-\(temperatureText)-\(identityLine)"
                if !registeredCityChipImages.contains(iconName) {
                    style.setImage(
                        MapChip.labeled(
                            MapChip.conditions(
                                iconAsset: conditions.iconAssetName,
                                temperatureText: temperatureText
                            ),
                            label: identityLine
                        ),
                        forName: iconName
                    )
                    registeredCityChipImages.insert(iconName)
                }
            } else {
                // Conditions not in yet: the emoji/pin disc as fallback (the
                // emoji already on the disc, only the label underneath).
                iconName = "oscar-city-pin-\(city.emoji ?? "plain")-\(customLabel)"
                if !registeredCityChipImages.contains(iconName) {
                    style.setImage(
                        MapChip.labeled(MapChip.pin(emoji: city.emoji), label: customLabel),
                        forName: iconName
                    )
                    registeredCityChipImages.insert(iconName)
                }
            }

            let feature = MLNPointFeature()
            feature.coordinate = coordinate
            feature.attributes = ["icon": iconName]
            features.append(feature)
            signature += "\(iconName)|\(city.lat)|\(city.lon);"
        }

        ensureCityChipLayer(in: style)
        // Other syncs add their layers topmost as data arrives (motion
        // arrows, value bubbles, cell heads, isobar labels) — re-hoist the
        // chips whenever anything has landed above them.
        if style.layers.last?.identifier != Self.cityChipLayerID,
           let layer = style.layer(withIdentifier: Self.cityChipLayerID) {
            style.removeLayer(layer)
            style.addLayer(layer)
        }

        guard signature != cityChipSignature else { return }
        cityChipSignature = signature
        (style.source(withIdentifier: Self.cityChipSourceID) as? MLNShapeSource)?
            .shape = MLNShapeCollectionFeature(shapes: features)
    }

    private func ensureCityChipLayer(in style: MLNStyle) {
        guard style.source(withIdentifier: Self.cityChipSourceID) == nil else { return }
        let source = MLNShapeSource(
            identifier: Self.cityChipSourceID,
            shape: MLNShapeCollectionFeature(shapes: [])
        )
        style.addSource(source)
        let layer = MLNSymbolStyleLayer(identifier: Self.cityChipLayerID, source: source)
        layer.iconImageName = NSExpression(forKeyPath: "icon")
        layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
        layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        // The identity line is baked into the image (the glyph server has no
        // emoji); top anchor + half-chip offset keeps the capsule centered
        // on the city no matter how tall the label makes the image.
        layer.iconAnchor = NSExpression(forConstantValue: "top")
        layer.iconOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: -MapChip.height / 2)))
        style.addLayer(layer)   // topmost — chips read above every overlay
    }
}
