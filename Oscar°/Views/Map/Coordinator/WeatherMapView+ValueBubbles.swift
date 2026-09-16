import CoreLocation
import MapLibre
import Metal
import OSLog
import Observation
import SwiftUI
import UIKit

// MARK: City value bubbles (model temperature + wind layers)

extension WeatherMapView.Coordinator {
    /// Value chips sampled from the CURRENT grid at a curated city list, in
    /// the saved-city chip design (MapChip): swatch dot = the palette color
    /// of the sampled index, text = the value in the user's unit, city name
    /// hanging below. Same data + same palette as the raster behind it, so
    /// the chips still double as a legend-in-context.
    ///
    /// NO collision system: three rank layers gated by zoom with
    /// allowsOverlap + ignoresPlacement. Collision placement fades symbols in
    /// over ~300 ms, which made every bubble FLASH on each scrub step —
    /// placement-less symbols swap content instantly.
    private static let bubbleSourceID = "oscar-value-bubbles"
    private static let bubbleRankMinZooms: [Float] = [2.5, 4.5, 6.0]

    func syncValueBubbles(style: MLNStyle, selection: WeatherTileLayer?, enabled: Bool,
                                  payload: RadarGridPayload?, frameKey: String?) {
        let isBubbleLayer: Bool
        switch selection {
        case .iconTemp, .ecmwfTemp,
             .iconWind, .ecmwfWind: isBubbleLayer = true
        default: isBubbleLayer = false
        }
        guard isBubbleLayer, enabled, let selection, let payload, let frameKey,
              let bounds = parent.modelGridState?.bounds,
              let palette = modelPalette, modelPaletteId == selection.colormapId else {
            if bubbleSyncKey != nil {
                removeValueBubbles(from: style)
            }
            return
        }

        let isWind = selection == .iconWind || selection == .ecmwfWind
        let unit = isWind
            ? parent.settingsService.windSpeedUnit
            : parent.settingsService.temperatureUnit

        // The location indicator (blue dot / selected city) must stay
        // readable — drop bubbles that would stack on top of it. The bubbles
        // ignore symbol placement, so MapLibre would happily draw both.
        var indicatorAnchors = [parent.coordinates]
        if let userCoordinate = mapView?.userLocation?.location?.coordinate {
            indicatorAnchors.append(userCoordinate)
        }
        func nearIndicator(lat: Double, lon: Double) -> Bool {
            indicatorAnchors.contains { anchor in
                let dLatKm = (anchor.latitude - lat) * 111.32
                let dLonKm = (anchor.longitude - lon) * 111.32 * cos(lat * .pi / 180)
                return dLatKm * dLatKm + dLonKm * dLonKm < 12 * 12
            }
        }
        let anchorKey = indicatorAnchors
            .map { String(format: "%.2f,%.2f", $0.latitude, $0.longitude) }
            .joined(separator: ";")
        let syncKey = "\(selection.rawValue)|\(frameKey)|\(unit)|\(anchorKey)"
        guard bubbleSyncKey != syncKey else { return }

        var features: [MLNPointFeature] = []
        var signature = ""
        features.reserveCapacity(MapValueBubbles.bubbleCities.count)
        for city in MapValueBubbles.bubbleCities {
            guard !nearIndicator(lat: city.lat, lon: city.lon) else { continue }
            guard let index = MapValueBubbles.sampleGridIndex(
                payload: payload, bounds: bounds, lat: city.lat, lon: city.lon) else { continue }
            // Inverse of the server's linear grid spans (Colormaps.gridIndex):
            // temperature maxValue 90 shift 40, wind_speed maxValue 50 shift 0.
            let label: String
            if isWind {
                let mps = (Double(index) - 1) / 254 * 50
                label = MapValueBubbles.windLabel(metersPerSecond: mps, unit: unit)
            } else {
                let celsius = (Double(index) - 1) / 254 * 90 - 40
                let shown = unit == "fahrenheit" ? celsius * 9 / 5 + 32 : celsius
                label = "\(Int(shown.rounded()))°"
            }

            // The value text is baked into the chip image, so the icon is
            // keyed by swatch bucket (~6 palette indices, buckets mean
            // different colors per layer) + label, registered lazily.
            let bucket = min(255, (Int(index) / 6) * 6 + 3)
            let iconName = "oscar-value-chip-\(selection.colormapId)-\(bucket)-\(label)"
            if !registeredBubbleIcons.contains(iconName) {
                let entry = palette[bucket]
                let color = UIColor(red: CGFloat(entry.r) / 255, green: CGFloat(entry.g) / 255,
                                    blue: CGFloat(entry.b) / 255, alpha: 1)
                style.setImage(MapChip.value(text: label, swatch: color), forName: iconName)
                registeredBubbleIcons.insert(iconName)
            }

            let feature = MLNPointFeature()
            feature.coordinate = CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
            feature.attributes = [
                "icon": iconName,
                "name": city.name,
                "rank": city.rank,
            ]
            features.append(feature)
            signature += "\(iconName)|\(city.name);"
        }

        ensureValueBubbleLayers(in: style)
        // Scrubbing adjacent hours often changes nothing visible at bubble
        // precision — skip the source swap entirely then.
        if signature != lastBubbleSignature {
            (style.source(withIdentifier: Self.bubbleSourceID) as? MLNShapeSource)?
                .shape = MLNShapeCollectionFeature(shapes: features)
            lastBubbleSignature = signature
        }
        bubbleSyncKey = syncKey
    }

    /// One shared source + one symbol layer per rank tier. Density comes from
    /// the tiers' minimum zoom levels, not from collision (see syncValueBubbles).
    private func ensureValueBubbleLayers(in style: MLNStyle) {
        guard style.source(withIdentifier: Self.bubbleSourceID) == nil else { return }
        let source = MLNShapeSource(identifier: Self.bubbleSourceID,
                                    shape: MLNShapeCollectionFeature(shapes: []))
        style.addSource(source)
        for (rank, minZoom) in Self.bubbleRankMinZooms.enumerated() {
            let layer = MLNSymbolStyleLayer(
                identifier: "\(Self.bubbleSourceID)-r\(rank)", source: source)
            layer.predicate = NSPredicate(format: "rank == %d", rank)
            layer.minimumZoomLevel = minZoom
            layer.iconImageName = NSExpression(forKeyPath: "icon")
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            layer.text = NSExpression(forKeyPath: "name")
            // The ONLY font stack the OpenFreeMap styles serve glyphs for — the
            // default Open Sans stack would 404 and the labels would vanish.
            layer.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
            layer.textFontSize = NSExpression(forConstantValue: 11)
            layer.textColor = NSExpression(forConstantValue: UIColor.white)
            layer.textHaloColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.45))
            layer.textHaloWidth = NSExpression(forConstantValue: 1)
            layer.textAllowsOverlap = NSExpression(forConstantValue: true)
            layer.textIgnoresPlacement = NSExpression(forConstantValue: true)
            // The city name hangs under the capsule.
            layer.textAnchor = NSExpression(forConstantValue: "top")
            layer.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.6)))
            style.addLayer(layer)   // topmost — value chips read above the labels
        }
    }

    private func removeValueBubbles(from style: MLNStyle) {
        for rank in Self.bubbleRankMinZooms.indices {
            if let layer = style.layer(withIdentifier: "\(Self.bubbleSourceID)-r\(rank)") {
                style.removeLayer(layer)
            }
        }
        if let source = style.source(withIdentifier: Self.bubbleSourceID) {
            style.removeSource(source)
        }
        bubbleSyncKey = nil
        lastBubbleSignature = nil
        registeredBubbleIcons.removeAll()
    }
}
