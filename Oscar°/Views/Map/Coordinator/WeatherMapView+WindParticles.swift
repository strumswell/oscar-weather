import CoreLocation
import MapLibre
import Metal
import OSLog
import Observation
import SwiftUI
import UIKit

// MARK: Wind particles

extension WeatherMapView.Coordinator {
    func syncWindParticles(selection: WeatherTileLayer?, state: ModelGridLayerState?) {
        guard let particleView = windParticleView else { return }
        let isWindLayer = parent.showWindParticles
            && (selection == .iconWind || selection == .ecmwfWind)

        guard isWindLayer, let state, let frameKey = state.currentFrameKey, let selection else {
            particleView.isHidden = true
            particleView.stopDisplayLink()
            if !isWindLayer {
                particleView.frameKey = nil
                particleView.activeLayer = nil
                lastWindFrameKey = nil
            }
            return
        }

        particleView.activeLayer = selection
        if lastWindFrameKey != frameKey {
            lastWindFrameKey = frameKey
            particleView.frameKey = frameKey

            let index = state.renderFrameIndex ?? state.currentFrameIndex
            let keys = state.frameKeys
            if !state.isMapInteracting {
                // Prefetch tiles for adjacent frames so scrubbing feels instant.
                if index > 0 { particleView.prefetchFrame(frameId: keys[index - 1], layer: selection) }
                if index + 1 < keys.count { particleView.prefetchFrame(frameId: keys[index + 1], layer: selection) }
            }
            // Evict tiles outside the ±2 frame window.
            let lo = max(0, index - 2)
            let hi = min(keys.count - 1, index + 2)
            if lo <= hi {
                let keepIds = Set(keys[lo...hi])
                Task {
                    await WindFieldCache.shared.evict(
                        retaining: keepIds, model: selection.windFieldPrefix)
                }
            }
        }

        particleView.isHidden = UIAccessibility.isReduceMotionEnabled
        if !UIAccessibility.isReduceMotionEnabled {
            particleView.startDisplayLinkIfNeeded()
        }
    }
}
