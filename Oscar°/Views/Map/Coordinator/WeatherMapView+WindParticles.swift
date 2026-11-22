import MapLibre
import UIKit

// MARK: Wind particles

extension WeatherMapView.Coordinator {
    func syncWindParticles(style: MLNStyle, selection: WeatherTileLayer?, state: ModelGridLayerState?) {
        let isWindLayer = selection == .iconWind || selection == .ecmwfWind

        guard isWindLayer, let selection else {
            removeWindLayer(from: style)
            windLoader.frameKey = nil
            windLoader.activeLayer = nil
            lastWindFrameKey = nil
            return
        }
        guard let state, let frameKey = state.currentFrameKey else {
            windLayer?.stop()
            return
        }

        windLoader.activeLayer = selection
        if lastWindFrameKey != frameKey {
            lastWindFrameKey = frameKey
            windLoader.frameKey = frameKey

            let index = state.renderFrameIndex ?? state.currentFrameIndex
            let keys = state.frameKeys
            if !state.isMapInteracting {
                if index > 0 { windLoader.prefetchFrame(frameId: keys[index - 1], layer: selection) }
                if index + 1 < keys.count { windLoader.prefetchFrame(frameId: keys[index + 1], layer: selection) }
            }
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

        guard !UIAccessibility.isReduceMotionEnabled else {
            windLayer?.stop()
            return
        }

        let layer: WindParticleLayer
        if let existing = windLayer {
            layer = existing
        } else {
            guard let modelLayer else { return }
            layer = WindParticleLayer(identifier: WeatherMapView.windLayerID)
            style.insertLayer(layer, above: modelLayer)
            windLayer = layer
            windLoader.layer = layer
        }
        layer.setUsesGlobalModelStyle(selection.isGlobalModel)
        layer.start()
    }

    private func removeWindLayer(from style: MLNStyle) {
        guard let layer = windLayer else { return }
        layer.stop()
        style.removeLayer(layer)
        windLayer = nil
    }
}
