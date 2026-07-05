//
//  WeatherMapPreview.swift
//  Oscar°
//
//  Small non-interactive weather-map preview card embedded in NowView.
//

import SwiftUI
import UIKit

// MARK: - Preview card (NowView)

/// Small non-interactive weather-map preview with its OWN radar state (the heavy
/// assets are shared via OscarRadarState's static caches, so this costs one metadata
/// fetch). The model tile layer state is shared with NowView, which drives its loads.
struct WeatherMapPreview: View {
    let settingsService: SettingService
    var modelGridState: ModelGridLayerState?
    @Environment(Location.self) private var location: Location
    @State private var radarState = OscarRadarState(renderMode: .preview)

    var body: some View {
        WeatherMapView(
            settingsService: settingsService,
            coordinates: location.coordinates,
            cities: LocationService.shared.city.cities,
            overlayOpacity: settingsService.mapOverlayOpacity,
            userActionAllowed: false,
            showWindParticles: false,
            oscarRadarState: radarState,
            modelGridState: modelGridState
        )
        .overlay(alignment: .topLeading) {
            if settingsService.oscarRadarLayer,
               radarState.hasAnyLoadedFrame,
               let timestamp = radarState.currentFrameTimestamp {
                RadarTimestampBadge(timestamp: timestamp, isLive: radarState.isCurrentFrameLive)
                    .padding(10)
            } else if settingsService.activeTileLayer != nil,
                      let modelGridState,
                      modelGridState.hasCurrentFrame,
                      let timestamp = modelGridState.currentFrameTimestamp {
                RadarTimestampBadge(timestamp: timestamp, isLive: false)
                    .padding(10)
            }
        }
        .overlay(alignment: .bottomLeading) {
            MapAttributionLabel()
                .padding(.leading, 10)
                .padding(.bottom, 6)
        }
        // Declared BEFORE the load task: re-picks the radar source whenever the
        // selected location changes (DWD → OPERA → NOAA → GFS precip fallback).
        .task(id: "\(location.coordinates.latitude)|\(location.coordinates.longitude)") {
            settingsService.autoSelectRadarSource(
                latitude: location.coordinates.latitude,
                longitude: location.coordinates.longitude)
        }
        .task {
            guard settingsService.oscarRadarLayer else { return }
            radarState.setProduct(settingsService.oscarRadarProduct)
            radarState.setRegion(settingsService.oscarRadarRegion)
            await radarState.loadCurrentFrame()
        }
        .task {
            // New radar frames land every ~5 min; refreshIfStale only re-fetches
            // once the shared metadata cache window has passed, so this stays
            // cheap while NowView sits on screen.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5 * 60))
                guard !Task.isCancelled, settingsService.oscarRadarLayer else { continue }
                await radarState.refreshIfStale()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            guard settingsService.oscarRadarLayer else { return }
            Task { await radarState.refreshIfStale() }
        }
        .onChange(of: settingsService.oscarRadarLayer) { _, isEnabled in
            guard isEnabled else { return radarState.pause() }
            radarState.setProduct(settingsService.oscarRadarProduct)
            radarState.setRegion(settingsService.oscarRadarRegion)
            if radarState.frames.isEmpty {
                Task { await radarState.loadCurrentFrame() }
            }
        }
        .onChange(of: settingsService.oscarRadarRegion) { _, newRegion in
            guard settingsService.oscarRadarLayer else { return }
            radarState.setRegion(newRegion)
            Task { await radarState.reloadForCurrentRegion() }
        }
        .onChange(of: settingsService.oscarRadarProduct) { _, newProduct in
            guard settingsService.oscarRadarLayer else { return }
            radarState.setProduct(newProduct)
            Task { await radarState.reloadForCurrentRegion() }
        }
    }
}
