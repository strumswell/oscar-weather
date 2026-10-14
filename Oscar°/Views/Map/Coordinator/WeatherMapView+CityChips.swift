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

    func syncCityChips(style: MLNStyle) {
        let store = CityConditionsStore.shared
        var features: [MLNPointFeature] = []
        var signature = ""
        for city in parent.cities where !city.selected {
            let coordinate = CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
            let customLabel = city.customLabel ?? ""
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
        layer.iconAnchor = NSExpression(forConstantValue: "top")
        layer.iconOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: -MapChip.height / 2)))
        style.addLayer(layer)
    }
}
