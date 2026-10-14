//
//  MapLayers.swift
//  Oscar°
//
//  The weather layers one map shows and how they load.
//

import CoreLocation
import Foundation

@MainActor
final class MapLayers {
    let timeline = CombinedTimelineState()
    let clouds = CloudLayerState()
    private let settings = SettingService.shared

    var radar: OscarRadarState { timeline.radar }
    var model: ModelGridLayerState { timeline.model }

    struct Continuation: Equatable {
        let layer: WeatherTileLayer
        let cutoff: Date
    }

    var continuation: Continuation? {
        guard settings.oscarRadarLayer, settings.radarModelContinuation,
              let last = radar.frameTimestamps.last.flatMap(parseFrameDate),
              let cutoff = Calendar.current.dateInterval(of: .hour, for: last)?.start else { return nil }
        return Continuation(layer: settings.oscarRadarRegion.continuationLayer, cutoff: cutoff)
    }

    func pickRadarSource(for coordinates: CLLocationCoordinate2D) {
        if let raw = UserDefaults.standard.string(forKey: "radarRegionLock"),
           let region = RadarRegion(rawValue: raw) {
            settings.activeTileLayer = nil
            settings.oscarRadarRegion = region
            settings.oscarRadarLayer = true
            return
        }
        settings.autoSelectRadarSource(latitude: coordinates.latitude, longitude: coordinates.longitude)
    }

    func syncCloudActivation() {
        clouds.setActive(settings.cloudLayerActive)
    }

    func loadActiveLayer() async {
        if settings.oscarRadarLayer {
            radar.setRegion(settings.oscarRadarRegion)
            if radar.frames.isEmpty {
                await radar.loadAllFrames()
            } else {
                await radar.refreshIfStale()
            }
        } else if let layer = settings.activeTileLayer {
            if model.currentLayer == layer, model.startsAfter == nil, model.hasAnyLoadedFrame {
                await model.refreshIfStale()
            } else {
                await model.loadLayer(layer)
            }
        }
    }

    func loadContinuation(_ continuation: Continuation?) async {
        guard let continuation,
              model.currentLayer != continuation.layer || model.startsAfter != continuation.cutoff else { return }
        await radar.waitForFrames()
        guard !Task.isCancelled else { return }
        await model.loadLayer(continuation.layer, after: continuation.cutoff)
    }

    func refreshIfStale() async {
        if settings.oscarRadarLayer {
            await radar.refreshIfStale()
        } else if settings.cloudLayerActive {
            clouds.refreshIfStale()
        } else if settings.activeTileLayer != nil {
            await model.refreshIfStale()
        }
    }

    func keepFresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5 * 60))
            guard !Task.isCancelled else { break }
            await refreshIfStale()
        }
    }

    func playActiveLayer() {
        if settings.oscarRadarLayer {
            timeline.play()
        } else if settings.cloudLayerActive {
            clouds.play()
        } else if settings.activeTileLayer != nil {
            model.play()
        }
    }

    func pause() {
        radar.pause()
        model.pause()
        clouds.pause()
    }

    func refreshCityChips() async {
        await CityConditionsStore.shared.refresh(
            coordinates: LocationService.shared.city.cities.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
            }
        )
    }
}
