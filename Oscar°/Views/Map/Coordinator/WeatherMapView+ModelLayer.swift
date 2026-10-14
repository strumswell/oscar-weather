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
        style: MLNStyle, selection: WeatherTileLayer?, visible: Bool, state: ModelGridLayerState?,
        bounds: OscarRadarBounds?, payload: RadarGridPayload?, frameKey: String?,
        next: (key: String, payload: RadarGridPayload)?, isPlaying: Bool,
        motion: RadarMotionData?, smoothMotion: Bool, softRendering: Bool,
        player: (any TimelinePlayerState)?
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
        layer.configure(bounds: bounds, opacity: visible ? Float(parent.overlayOpacity) : 0)
        layer.setSampling(softRendering ? .soft : .hard)
        layer.setMotion(motion)

        if modelPaletteId != selection.colormapId {
            modelPaletteId = selection.colormapId
            modelPalette = nil
            layer.clearPalette()
            layer.purgeTextures()
            lastModelFrameKey = nil
            let colormapId = selection.colormapId
            Task { @MainActor [weak self] in
                guard let palette = await ServerPalettes.resolve(id: colormapId) else {
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
            syncPlayback(of: layer, state: player ?? state, playing: isPlaying && payload != nil,
                         interval: 0.8, interpolate: smoothMotion && !UIAccessibility.isReduceMotionEnabled)
        }

        guard let payload, let frameKey else { return }
        let pairKey = "\(frameKey)|\(next?.key ?? "-")"
        guard lastModelFrameKey != pairKey else { return }
        guard let textureA = layer.texture(key: frameKey, payload: payload) else {
            scheduleSyncRetry()
            return
        }
        let textureB = next.flatMap { layer.texture(key: $0.key, payload: $0.payload) }
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
