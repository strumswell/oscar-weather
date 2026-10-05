//
//  MapLayers.swift
//  Oscar°
//
//  The weather layers one map shows and how they load.
//

import CoreLocation
import Foundation

/// The weather layers one map shows (radar continued by the model, model
/// layers, satellite clouds) and how they load and refresh. The Karten tab
/// and the forecast's map preview each own one: every map's radar layer
/// advances its state from its own display link, so two maps sharing one
/// state would play it at double speed.
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

    /// The region's model, cut at the start of the last radar frame's hour: its
    /// frames after that continue the radar. nil while the continuation is off
    /// or the radar hasn't loaded.
    var continuation: Continuation? {
        guard settings.oscarRadarLayer, settings.radarModelContinuation,
              let last = radar.frameTimestamps.last.flatMap(parseFrameDate),
              let cutoff = Calendar.current.dateInterval(of: .hour, for: last)?.start else { return nil }
        return Continuation(layer: settings.oscarRadarRegion.continuationLayer, cutoff: cutoff)
    }

    /// The radar source covering the place. Capture knob: `-radarRegionLock
    /// brasil` pins the coverage (used with `-mapInitialCenter` to screenshot
    /// the layer-picker preview tiles), overriding the location-based pick.
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

    /// Cloud activation is settings-derived; setActive no-ops when unchanged.
    func syncCloudActivation() {
        clouds.setActive(settings.cloudLayerActive)
    }

    /// Full load of the picked layer the first time, cheap staleness checks after that.
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

    /// The model hours after the radar's nowcast. The cutoff moves per hour,
    /// so radar refreshes within it load nothing.
    func loadContinuation(_ continuation: Continuation?) async {
        guard let continuation,
              model.currentLayer != continuation.layer || model.startsAfter != continuation.cutoff else { return }
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

    /// A map left open across server updates re-fetches once the metadata expires.
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

    /// Stops playback; frames stay cached for the next visit.
    func pause() {
        radar.pause()
        model.pause()
        clouds.pause()
    }

    /// The saved-city chips need the batch conditions even when the map opens
    /// before the locations list ever fetched them. The store throttles to one
    /// fetch per 5 minutes.
    func refreshCityChips() async {
        await CityConditionsStore.shared.refresh(
            coordinates: LocationService.shared.city.cities.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
            }
        )
    }
}
