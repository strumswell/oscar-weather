import CoreLocation
import MapLibre
import Metal
import OSLog
import Observation
import SwiftUI
import UIKit

// MARK: ICON-D2 / ECMWF model layer (value grids + palette, like the radar)

extension WeatherMapView.Coordinator {
    func syncModelLayer(
        style: MLNStyle, selection: WeatherTileLayer?, state: ModelGridLayerState?,
        bounds: OscarRadarBounds?, payload: RadarGridPayload?, frameKey: String?,
        next: (key: String, payload: RadarGridPayload)?, isPlaying: Bool,
        motion: RadarMotionData?, smoothMotion: Bool, softRendering: Bool
    ) {
        guard let selection, let state else {
            removeModelLayer(from: style)
            return
        }
        guard let bounds else { return }

        let layer: RadarCustomStyleLayer
        if let existing = modelLayer {
            layer = existing
        } else {
            layer = RadarCustomStyleLayer(identifier: WeatherMapView.modelLayerID)
            insertOverlayLayer(layer, in: style)
            modelLayer = layer
        }
        layer.configure(bounds: bounds, opacity: Float(parent.overlayOpacity))
        layer.setSampling(softRendering ? .soft : .hard)
        layer.setMotion(motion)

        // Variable switch: grid indices mean different things per palette and
        // frame keys collide across variables — palette and textures must go.
        if modelPaletteId != selection.colormapId {
            modelPaletteId = selection.colormapId
            modelPalette = nil
            layer.clearPalette()
            layer.purgeTextures()
            lastModelFrameKey = nil
            let colormapId = selection.colormapId
            Task { @MainActor [weak self] in
                guard let palette = await ModelGridLayerState.palette(for: colormapId) else {
                    guard let self, self.modelPaletteId == colormapId else { return }
                    self.modelPaletteId = nil
                    return
                }
                guard let self, self.modelPaletteId == colormapId else { return }
                self.modelPalette = palette
                self.syncAll()
            }
            return
        }
        // Re-applied until it sticks: `setPalette` needs the Metal device from the
        // layer's `didMove`, which MapLibre can deliver AFTER a fast (local/cached)
        // palette fetch — a one-shot set would be lost forever.
        if !layer.hasPalette, let modelPalette {
            layer.setPalette(modelPalette)
            layer.setNeedsDisplay()
        }

        if lastModelBounds != bounds {
            layer.purgeTextures()
            lastModelBounds = bounds
            lastModelFrameKey = nil
        }

        defer {
            // Same playback ownership rule as the radar layer: while playing,
            // the layer's display link owns phase + advancement (hourly frames
            // morph along the model flow — precip — or cross-fade in data
            // space); the state's 0.8 s Timer would double-advance, so it is
            // cancelled while the layer runs.
            // Fullscreen only: the NowView preview SHARES this state — a second
            // display link would double-advance every tick.
            if isPlaying, payload != nil, parent.userActionAllowed {
                state.cancelInternalTimer()
                layer.startPlayback(
                    interval: 0.8,
                    interpolate: smoothMotion && !UIAccessibility.isReduceMotionEnabled
                ) { [weak state] in
                    state?.advanceFrame()
                }
            } else if layer.isPlaybackActive {
                layer.stopPlayback()
            }
        }

        guard let payload, let frameKey else { return }
        // Re-display when either end of the pair changes (the next frame can
        // arrive later than the current one during progressive loading).
        let pairKey = "\(frameKey)|\(next?.key ?? "-")"
        guard lastModelFrameKey != pairKey else { return }
        guard let textureA = layer.texture(key: frameKey, payload: payload) else {
            // No Metal device yet (didMove pending). Do NOT stamp pairKey — a
            // cached palette + grid can resolve before didMove, and nothing
            // observable changes when the device lands, so nudge a retry.
            scheduleSyncRetry()
            return
        }
        let textureB = next.flatMap { layer.texture(key: $0.key, payload: $0.payload) }
        // Flow lookup, precipitation only — temperature/wind blend in data
        // space without warping. Exact adjacent pair first; FROM-frame fallback
        // (rescaled by the real timestamp gap) when the displayed pair skips
        // served frames. Hourly pairs arrive with gap_minutes=60, right at the
        // radar path's ceiling: the shader scales the per-5-min field by
        // 60/5 = 12 — the full hour of motion, dry pairs share a zero field
        // (degrades to the plain cross-fade). Larger gaps (skipped frames
        // while loading) never morph.
        var flowFieldIndex: Int?
        var flowScale: Float = 0
        if selection.morphsAlongMotion, let motion, let next {
            let pair = motion.pairs["\(frameKey)|\(next.key)"] ?? motion.pairsByFrom[frameKey]
            if let pair,
               let from = state.timestamp(forKey: frameKey),
               let to = state.timestamp(forKey: next.key),
               let gap = OscarRadarState.minutesBetween(from, to),
               gap > 0, gap <= 60 {
                flowFieldIndex = pair.fieldIndex
                flowScale = Float(gap) / Float(motion.stepMinutes)
            }
        }
        layer.display(frameA: textureA, frameB: textureB,
                      flowFieldIndex: flowFieldIndex, flowScale: flowScale)
        lastModelFrameKey = pairKey
    }

    private func removeModelLayer(from style: MLNStyle) {
        guard let layer = modelLayer else { return }
        layer.stopPlayback()
        layer.purgeTextures()
        style.removeLayer(layer)
        modelLayer = nil
        modelPaletteId = nil
        modelPalette = nil
        lastModelFrameKey = nil
        lastModelBounds = nil
    }
}
