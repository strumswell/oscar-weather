import CoreLocation
import MapLibre
import Metal
import OSLog
import Observation
import SwiftUI
import UIKit

// MARK: Radar (custom layer + motion morph + arrows)

extension WeatherMapView.Coordinator {
    func syncRadar(
        style: MLNStyle, active: Bool, state: OscarRadarState?, product: RadarProduct,
        bounds: OscarRadarBounds?, frame: OscarRadarFrame?, next: OscarRadarFrame?,
        renderedIndex: Int, loadedCount: Int, frameCount: Int,
        isPlaying: Bool, motion: RadarMotionData?, smoothMotion: Bool,
        softRendering: Bool, arrowsEnabled: Bool
    ) {
        guard active, let state else {
            removeArrowLayer(from: style)
            if let layer = radarLayer {
                layer.stopPlayback()
                layer.purgeTextures()
                style.removeLayer(layer)
                radarLayer = nil
                lastFrameKey = nil
                lastRenderIndex = -1
                lastBounds = nil
                radarPaletteId = nil
            }
            return
        }
        guard let bounds else { return blocked("no radar bounds (metadata not loaded)") }

        let layer: RadarCustomStyleLayer
        if let existing = radarLayer {
            layer = existing
        } else {
            layer = RadarCustomStyleLayer(identifier: WeatherMapView.radarLayerID)
            insertOverlayLayer(layer, in: style)
            radarLayer = layer
        }

        layer.configure(bounds: bounds, opacity: Float(parent.overlayOpacity))
        // Typed grids are block-coded (type × intensity) — the categorical modes
        // pick the block from the nearest sample; the soft variant smooths the
        // intensity inside it (Weichzeichnen without fabricated types).
        layer.setSampling(product == .precipitationTyped
                          ? (softRendering ? .categoricalSoft : .categorical)
                          : softRendering ? .soft : .hard)
        layer.setMotion(motion)

        // Product switch on the same layer: palette AND textures must go —
        // grid indices mean different things per palette and frame keys are
        // bare timestamps that collide across products.
        if radarPaletteId != product.colormapId {
            radarPaletteId = product.colormapId
            layer.clearPalette()
            layer.purgeTextures()
            lastFrameKey = nil
            lastRenderIndex = -1
        }
        if !layer.hasPalette, !isFetchingPalette {
            isFetchingPalette = true
            let paletteId = product.colormapId
            Task { @MainActor [weak self, weak layer] in
                let palette = await OscarRadarState.resolvedPalette(id: paletteId)
                if self?.radarPaletteId == paletteId {
                    layer?.setPalette(palette)
                    layer?.setNeedsDisplay()
                }
                self?.isFetchingPalette = false
            }
        }

        if lastBounds != bounds {
            // Region switch: frame keys are bare timestamps that collide across
            // regions — the texture cache must go too.
            layer.purgeTextures()
            lastBounds = bounds
            lastFrameKey = nil
            lastRenderIndex = -1
            recenterIntoRadarBoundsIfNeeded(animated: parent.userActionAllowed)
        }

        // Typed playback morphs too — categorical mode blends in color space,
        // so no index sweeps through unrelated types.
        let interpolate = smoothMotion && !UIAccessibility.isReduceMotionEnabled

        defer {
            // Playback ownership mirrors the old Metal overlay: the layer's display
            // link owns phase + frame advancement; the state's 0.5 s Timer would
            // double-advance, so it is cancelled while the layer runs.
            if isPlaying, frame != nil {
                state.cancelInternalTimer()
                layer.startPlayback(interpolate: interpolate) { [weak state] in
                    state?.advanceFrame()
                }
            } else if layer.isPlaybackActive {
                layer.stopPlayback()
            }
            syncArrowLayer(style: style, state: state, frame: frame, isPlaying: isPlaying,
                           enabled: arrowsEnabled)
        }

        guard let frame else {
            return blocked("no current radar frame (loaded=\(loadedCount)/\(frameCount))")
        }
        guard lastFrameKey != frame.key || lastRenderIndex != renderedIndex else { return }
        blocked(nil)

        guard let textureA = layer.texture(for: frame) else {
            // No Metal device yet (didMove pending) — retry without stamping
            // lastFrameKey, or this frame would never be re-displayed.
            scheduleSyncRetry()
            return
        }
        let textureB = next.flatMap { layer.texture(for: $0) }
        // Flow lookup: exact adjacent pair first; when the displayed pair skips
        // served frames (progressive loading), fall back to the FROM frame's
        // field and rescale by the real timestamp gap. Never morph backwards
        // across the loop seam (negative gap) or across data holes (> 1 h).
        var flowFieldIndex: Int?
        var flowScale: Float = 0
        if let motion, let next {
            let pair = motion.pairs["\(frame.key)|\(next.key)"] ?? motion.pairsByFrom[frame.key]
            if let pair,
               let gap = OscarRadarState.minutesBetween(frame.timestamp, next.timestamp),
               gap > 0, gap <= 60 {
                flowFieldIndex = pair.fieldIndex
                flowScale = Float(gap) / Float(motion.stepMinutes)
            }
        }
        layer.display(frameA: textureA, frameB: textureB,
                      flowFieldIndex: flowFieldIndex, flowScale: flowScale)
        lastFrameKey = frame.key
        lastRenderIndex = renderedIndex
    }

    /// Motion arrows for the CURRENT observed frame, built client-side from the
    /// /motion flow field + the frame's in-RAM value grid (one point feature per
    /// coarse cell that carries precipitation). Replaces the server raster
    /// vector tiles, whose stretched old-zoom tiles flashed huge arrows during
    /// zoom transitions — symbol icons are screen-space (no scaling flicker)
    /// and MapLibre's collision thins them automatically when zooming out.
    /// Hidden during playback, like the raster tiles were.
    private static let arrowSourceIdentifier = "oscar-motion-arrows"
    private static let arrowImageName = "oscar-motion-arrow"

    func syncArrowLayer(style: MLNStyle, state: OscarRadarState,
                                frame: OscarRadarFrame?, isPlaying: Bool, enabled: Bool) {
        let desiredID: String?
        if let frame, !isPlaying, enabled, let motion = state.motion,
           let pair = motion.pairsByFrom[frame.key] {
            desiredID = "\(state.region.pathComponent)-\(frame.key)-\(pair.fieldIndex)"
        } else {
            desiredID = nil
        }
        guard desiredID != arrowSourceID else { return }
        guard let desiredID, let frame, let motion = state.motion,
              let pair = motion.pairsByFrom[frame.key], let bounds = state.bounds else {
            removeArrowLayer(from: style)
            return
        }

        let features = RadarMotionArrows.arrowFeatures(
            motion: motion, fieldIndex: pair.fieldIndex,
            grid: frame.gridPayload, bounds: bounds)
        let shape = MLNShapeCollectionFeature(shapes: features)

        if let source = style.source(withIdentifier: Self.arrowSourceIdentifier) as? MLNShapeSource {
            source.shape = shape
        } else {
            style.setImage(RadarArrowGeometry.arrowImage(), forName: Self.arrowImageName)
            let source = MLNShapeSource(identifier: Self.arrowSourceIdentifier, shape: shape)
            let layer = MLNSymbolStyleLayer(identifier: Self.arrowSourceIdentifier, source: source)
            layer.iconImageName = NSExpression(forConstantValue: Self.arrowImageName)
            layer.iconRotation = NSExpression(forKeyPath: "rotation")
            layer.iconScale = NSExpression(forKeyPath: "scale")
            // Map-aligned: arrows keep their geographic direction when the map
            // rotates; their SIZE stays screen-space at every zoom.
            layer.iconRotationAlignment = NSExpression(forConstantValue: "map")
            layer.iconAllowsOverlap = NSExpression(forConstantValue: false)
            layer.iconOpacity = NSExpression(forConstantValue: 0.9)
            style.addSource(source)
            style.addLayer(layer)     // topmost — arrows read above the labels
        }
        arrowSourceID = desiredID
    }

    private func removeArrowLayer(from style: MLNStyle) {
        guard arrowSourceID != nil else { return }
        if let layer = style.layer(withIdentifier: Self.arrowSourceIdentifier) { style.removeLayer(layer) }
        if let source = style.source(withIdentifier: Self.arrowSourceIdentifier) { style.removeSource(source) }
        arrowSourceID = nil
    }
}
