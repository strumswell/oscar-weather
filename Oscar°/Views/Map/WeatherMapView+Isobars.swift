import CoreLocation
import MapLibre
import Metal
import OSLog
import Observation
import SwiftUI
import UIKit

// MARK: Isobars (Großwetterlage overlay)

extension WeatherMapView.Coordinator {
    /// MSLP isolines + H/T pressure centers (server `/models/{model}/frames/
    /// {key}/pressure/isolines`) over the active model layer — the classic
    /// Großwetterlage look on top of the pressure, temperature, or wind fill.
    /// The per-frame GeoJSON swaps into one shared source while scrubbing (the
    /// value-bubble pattern); fetched shapes are cached per frame key, so a
    /// second playback loop is free.
    func syncIsobars(style: MLNStyle, active: Bool,
                             selection: WeatherTileLayer?, frameKey: String?) {
        guard active, let selection, let frameKey else {
            if isobarSyncKey != nil { removeIsobarLayers(from: style) }
            return
        }
        let cacheKey = "\(selection.framesEndpoint)/\(frameKey)"

        if isobarShapes[cacheKey] == nil,
           !isobarFetchesInFlight.contains(cacheKey),
           isobarFailures[cacheKey].map({ Date().timeIntervalSince($0) > 120 }) ?? true {
            isobarFetchesInFlight.insert(cacheKey)
            Task { @MainActor [weak self] in
                defer { self?.isobarFetchesInFlight.remove(cacheKey) }
                do {
                    let data = try await APIClient.shared.getPressureIsolines(
                        framesEndpoint: selection.framesEndpoint, frameKey: frameKey)
                    guard let self, !self.isTornDown else { return }
                    guard let shape = try? MLNShape(
                        data: data, encoding: String.Encoding.utf8.rawValue) else {
                        self.isobarFailures[cacheKey] = Date()
                        return
                    }
                    // Frame keys are valid-time stable, so day over day the cache
                    // only grows — reset it before it does.
                    if self.isobarShapes.count > 96 { self.isobarShapes.removeAll() }
                    self.isobarShapes[cacheKey] = shape
                    self.isobarFailures[cacheKey] = nil
                    self.syncAll()
                } catch {
                    weatherMapLogger.error("Isobar fetch failed: \(error.localizedDescription, privacy: .public)")
                    self?.isobarFailures[cacheKey] = Date()
                }
            }
        }

        guard let shape = isobarShapes[cacheKey] else {
            clearIsobarSourceIfNeeded(in: style, nextKey: cacheKey)
            return
        }
        ensureIsobarLayers(in: style)
        guard isobarSyncKey != cacheKey else { return }
        // The new frame loads into the hidden buffer, then the opacity
        // transitions swap the two — the same soft frame change the grid
        // fill gets from its Metal cross-fade.
        let incoming = 1 - isobarActiveBuffer
        (style.source(withIdentifier: WeatherMapView.isobarSourceID(incoming)) as? MLNShapeSource)?
            .shape = shape
        setIsobarBufferOpacities(in: style, visibleBuffer: incoming)
        isobarActiveBuffer = incoming
        isobarSyncKey = cacheKey
        scheduleRetiredIsobarCleanup(in: style)
    }

    private func clearIsobarSourceIfNeeded(in style: MLNStyle, nextKey: String) {
        guard isobarSyncKey != nil, isobarSyncKey != nextKey else { return }
        setIsobarBufferOpacities(in: style, visibleBuffer: nil)
        isobarSyncKey = nil
    }

    /// Animated by the transitions set at layer creation; nil hides both buffers.
    private func setIsobarBufferOpacities(in style: MLNStyle, visibleBuffer: Int?) {
        for buffer in 0..<WeatherMapView.isobarBufferCount {
            let visible = buffer == visibleBuffer
            if let casing = style.layer(
                withIdentifier: WeatherMapView.isobarCasingLayerID(buffer)) as? MLNLineStyleLayer {
                casing.lineOpacity = NSExpression(forConstantValue: visible ? 0.28 : 0)
            }
            if let line = style.layer(
                withIdentifier: WeatherMapView.isobarLineLayerID(buffer)) as? MLNLineStyleLayer {
                line.lineOpacity = NSExpression(forConstantValue: visible ? 0.95 : 0)
            }
            for id in [WeatherMapView.isobarLabelLayerID(buffer),
                       WeatherMapView.isobarCenterLayerID(buffer),
                       WeatherMapView.isobarCenterValueLayerID(buffer)] {
                (style.layer(withIdentifier: id) as? MLNSymbolStyleLayer)?
                    .textOpacity = NSExpression(forConstantValue: visible ? 1 : 0)
            }
        }
    }

    /// Empties the faded-out buffer once the cross-fade is over: its
    /// zero-opacity line labels would otherwise keep competing with the
    /// visible buffer's in collision placement.
    private func scheduleRetiredIsobarCleanup(in style: MLNStyle) {
        isobarCleanupGeneration += 1
        let generation = isobarCleanupGeneration
        let retired = 1 - isobarActiveBuffer
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !self.isTornDown,
                  self.isobarCleanupGeneration == generation else { return }
            (style.source(withIdentifier: WeatherMapView.isobarSourceID(retired)) as? MLNShapeSource)?
                .shape = MLNShapeCollectionFeature(shapes: [])
        }
    }

    /// Per buffer: one source; casing + core line pair (readable over both the
    /// dark low end and the near-white 1013 center of the pressure fill),
    /// inline hPa labels, and the H/T center letters with their central
    /// pressure. All opacities start at 0 and carry fade transitions — the
    /// A/B swap in syncIsobars animates without any per-frame animation code.
    private func ensureIsobarLayers(in style: MLNStyle) {
        guard style.source(withIdentifier: WeatherMapView.isobarSourceID(0)) == nil else { return }
        for buffer in 0..<WeatherMapView.isobarBufferCount {
            addIsobarBuffer(buffer, to: style)
        }
    }

    private func addIsobarBuffer(_ buffer: Int, to style: MLNStyle) {
        let source = MLNShapeSource(identifier: WeatherMapView.isobarSourceID(buffer),
                                    shape: MLNShapeCollectionFeature(shapes: []))
        style.addSource(source)

        let fade = MLNTransition(duration: 0.25, delay: 0)
        // Lines carry `level`, the H/T points carry `kind` — the predicates keep
        // each layer to its half of the shared FeatureCollection.
        let isIsobar = NSPredicate(format: "level != NIL")
        let isCenter = NSPredicate(format: "kind != NIL")
        // Index isobars (multiples of 10/20 hPa) draw bolder.
        func indexWidth(_ index: Double, _ regular: Double) -> NSExpression {
            NSExpression(forConditional: NSPredicate(format: "index == YES"),
                         trueExpression: NSExpression(forConstantValue: index),
                         falseExpression: NSExpression(forConstantValue: regular))
        }

        let casing = MLNLineStyleLayer(
            identifier: WeatherMapView.isobarCasingLayerID(buffer), source: source)
        casing.predicate = isIsobar
        casing.lineColor = NSExpression(forConstantValue: UIColor.black)
        casing.lineOpacity = NSExpression(forConstantValue: 0)
        casing.lineOpacityTransition = fade
        casing.lineWidth = indexWidth(3.2, 2.2)
        casing.lineCap = NSExpression(forConstantValue: "round")
        casing.lineJoin = NSExpression(forConstantValue: "round")
        insertOverlayLayer(casing, in: style)

        let line = MLNLineStyleLayer(
            identifier: WeatherMapView.isobarLineLayerID(buffer), source: source)
        line.predicate = isIsobar
        line.lineColor = NSExpression(forConstantValue: UIColor.white)
        line.lineOpacity = NSExpression(forConstantValue: 0)
        line.lineOpacityTransition = fade
        line.lineWidth = indexWidth(1.8, 1.0)
        line.lineCap = NSExpression(forConstantValue: "round")
        line.lineJoin = NSExpression(forConstantValue: "round")
        insertOverlayLayer(line, in: style)

        // Inline hPa labels along the lines, above the basemap labels.
        let labels = MLNSymbolStyleLayer(
            identifier: WeatherMapView.isobarLabelLayerID(buffer), source: source)
        labels.predicate = isIsobar
        labels.symbolPlacement = NSExpression(forConstantValue: "line")
        labels.symbolSpacing = NSExpression(forConstantValue: 320)
        labels.maximumTextAngle = NSExpression(forConstantValue: 30)
        labels.text = NSExpression(forKeyPath: "label")
        // The ONLY font stack the OpenFreeMap styles serve glyphs for.
        labels.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
        labels.textFontSize = NSExpression(forConstantValue: 10)
        labels.textColor = NSExpression(forConstantValue: UIColor.white)
        labels.textHaloColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.55))
        labels.textHaloWidth = NSExpression(forConstantValue: 1.1)
        labels.textOpacity = NSExpression(forConstantValue: 0)
        labels.textOpacityTransition = fade
        style.addLayer(labels)

        // Neutral pressure-center labels avoid conflicting with the pressure
        // fill palette, where low pressure is blue and high pressure is red.
        let centerColor = NSExpression(forConstantValue: UIColor.black)
        let centers = MLNSymbolStyleLayer(
            identifier: WeatherMapView.isobarCenterLayerID(buffer), source: source)
        centers.predicate = isCenter
        centers.text = NSExpression(forKeyPath: "kind")
        centers.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
        centers.textFontSize = NSExpression(forConstantValue: 24)
        centers.textColor = centerColor
        centers.textHaloColor = NSExpression(forConstantValue: UIColor.white.withAlphaComponent(0.85))
        centers.textHaloWidth = NSExpression(forConstantValue: 1.4)
        centers.textAllowsOverlap = NSExpression(forConstantValue: true)
        centers.textIgnoresPlacement = NSExpression(forConstantValue: true)
        centers.textOpacity = NSExpression(forConstantValue: 0)
        centers.textOpacityTransition = fade
        style.addLayer(centers)

        let centerValues = MLNSymbolStyleLayer(
            identifier: WeatherMapView.isobarCenterValueLayerID(buffer), source: source)
        centerValues.predicate = isCenter
        centerValues.text = NSExpression(forKeyPath: "label")
        centerValues.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
        centerValues.textFontSize = NSExpression(forConstantValue: 10)
        centerValues.textColor = centerColor
        centerValues.textHaloColor = NSExpression(forConstantValue: UIColor.white.withAlphaComponent(0.85))
        centerValues.textHaloWidth = NSExpression(forConstantValue: 1.2)
        centerValues.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.5)))
        centerValues.textAllowsOverlap = NSExpression(forConstantValue: true)
        centerValues.textIgnoresPlacement = NSExpression(forConstantValue: true)
        centerValues.textOpacity = NSExpression(forConstantValue: 0)
        centerValues.textOpacityTransition = fade
        style.addLayer(centerValues)
    }

    private func removeIsobarLayers(from style: MLNStyle) {
        for buffer in 0..<WeatherMapView.isobarBufferCount {
            for id in [WeatherMapView.isobarCenterValueLayerID(buffer),
                       WeatherMapView.isobarCenterLayerID(buffer),
                       WeatherMapView.isobarLabelLayerID(buffer),
                       WeatherMapView.isobarLineLayerID(buffer),
                       WeatherMapView.isobarCasingLayerID(buffer)] {
                if let layer = style.layer(withIdentifier: id) { style.removeLayer(layer) }
            }
            if let source = style.source(withIdentifier: WeatherMapView.isobarSourceID(buffer)) {
                style.removeSource(source)
            }
        }
        isobarSyncKey = nil
        isobarActiveBuffer = 0
    }
}
