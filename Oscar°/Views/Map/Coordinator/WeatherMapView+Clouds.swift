import CoreLocation
import MapLibre
import Metal
import OSLog
import Observation
import SwiftUI
import UIKit

// MARK: Satellite clouds (own layer with its own timeline)

extension WeatherMapView.Coordinator {
    /// The clouds are a SELECTABLE layer like the model layers: the cloud
    /// state owns pair + playback via the display link. (The former
    /// radar-synced underlay mode is gone — clouds, radar and model layers
    /// are mutually exclusive.)
    func syncClouds(
        style: MLNStyle, active: Bool,
        state: CloudLayerState?, bounds: OscarRadarBounds?, motion: RadarMotionData?,
        cloudIsPlaying: Bool, smoothMotion: Bool
    ) {
        guard active, let state else {
            if let layer = cloudsLayer {
                layer.purgeTextures()
                style.removeLayer(layer)
                cloudsLayer = nil
                lastCloudsPairKey = nil
                lastCloudsBounds = nil
            }
            return
        }
        guard let bounds else { return }   // metadata not loaded yet

        let layer: RadarCustomStyleLayer
        if let existing = cloudsLayer {
            layer = existing
        } else {
            layer = RadarCustomStyleLayer(identifier: WeatherMapView.cloudsLayerID)
            insertOverlayLayer(layer, in: style)
            cloudsLayer = layer
        }
        layer.configure(bounds: bounds, opacity: Float(parent.overlayOpacity))
        // Clouds are soft by nature — the hard/sharp toggle is a radar look.
        layer.setSampling(.soft)
        layer.setMotion(motion)

        if !layer.hasPalette {
            if let cloudsPalette {
                layer.setPalette(cloudsPalette)
                layer.setNeedsDisplay()
            } else if !cloudsPaletteFetching {
                cloudsPaletteFetching = true
                Task { @MainActor [weak self] in
                    // Server palette with a local fallback — always resolves.
                    let palette = await CloudLayerState.resolvedPalette()
                    guard let self else { return }
                    self.cloudsPaletteFetching = false
                    self.cloudsPalette = palette
                    self.syncAll()
                }
            }
        }

        if lastCloudsBounds != bounds {
            layer.purgeTextures()
            lastCloudsBounds = bounds
            lastCloudsPairKey = nil
        }

        defer {
            if cloudIsPlaying, state.currentFrameKeyed != nil {
                state.cancelInternalTimer()
                layer.startPlayback(
                    interval: 0.5,
                    interpolate: smoothMotion && !UIAccessibility.isReduceMotionEnabled
                ) { [weak state] in
                    state?.advanceFrame()
                }
            } else if layer.isPlaybackActive {
                layer.stopPlayback()
            }
        }
        guard let current = state.currentFrameKeyed else { return }
        let next = state.nextFrameKeyed
        let pairKey = "\(current.key)|\(next?.key ?? "-")"
        guard lastCloudsPairKey != pairKey else { return }
        guard let textureA = layer.texture(key: current.key, payload: current.payload) else {
            scheduleSyncRetry()
            return
        }
        let textureB = next.flatMap { layer.texture(key: $0.key, payload: $0.payload) }
        var flowFieldIndex: Int?
        var flowScale: Float = 0
        if let motion = state.motion, let next {
            let pair = motion.pairs["\(current.key)|\(next.key)"] ?? motion.pairsByFrom[current.key]
            if let pair,
               let from = state.timestamp(forKey: current.key),
               let to = state.timestamp(forKey: next.key),
               let gap = OscarRadarState.minutesBetween(from, to),
               gap > 0, gap <= 60 {
                flowFieldIndex = pair.fieldIndex
                flowScale = Float(gap) / Float(motion.stepMinutes)
            }
        }
        layer.display(frameA: textureA, frameB: textureB,
                      flowFieldIndex: flowFieldIndex, flowScale: flowScale)
        lastCloudsPairKey = pairKey
    }
}
