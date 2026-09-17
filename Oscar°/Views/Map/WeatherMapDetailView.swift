//
//  WeatherMapDetailView.swift
//  Oscar°
//
//  Fullscreen weather map: legend, layer picker entry point, and the shared
//  timeline chip.
//

import CoreLocation
import SwiftUI
import UIKit

// MARK: - Fullscreen detail view

/// Fullscreen weather map: legend, layer menu, and the shared timeline chip
/// (radar or model layer, depending on what's active). Hosted as the Karten tab,
/// so it stays alive across tab switches: loads are guarded against re-runs and
/// playback pauses when the tab disappears.
struct WeatherMapDetailView: View {
    let settingsService: SettingService
    @Environment(Location.self) private var location: Location
    @Environment(\.scenePhase) private var scenePhase
    @State private var radarState = OscarRadarState()
    @State private var modelGridState = ModelGridLayerState()
    @State private var cloudLayerState = CloudLayerState()
    @State private var isLayerPickerPresented = false
    // sheet(item:), not sheet(isPresented:) + separate array state: the isPresented
    // variant renders its content once with the PRE-tap (empty) array on the first
    // presentation — the classic stale-state sheet bug.
    @State private var tappedAlerts: TappedAlerts?
    @State private var tappedCell: StormCellInfo?

    private struct TappedAlerts: Identifiable {
        let id = UUID()
        let alerts: [WeatherAlertInfo]
    }

    var body: some View {
        ZStack {
            WeatherMapView(
                settingsService: settingsService,
                coordinates: location.coordinates,
                cities: LocationService.shared.city.cities,
                overlayOpacity: settingsService.mapOverlayOpacity,
                oscarRadarState: radarState,
                modelGridState: modelGridState,
                cloudLayerState: cloudLayerState,
                onAlertsTapped: { alerts in
                    tappedAlerts = TappedAlerts(alerts: alerts)
                },
                onCellTapped: { cell in
                    tappedCell = cell
                }
            )
            .ignoresSafeArea()

            // Timestamp badge + legend — top-left. The badge doubles as the
            // scrub readout: eyes travel up from the scrubber to read the time
            // here, so it stays even though the chip header shows it too.
            VStack {
                HStack(alignment: .top) {
                    MapLegendStack(settingsService: settingsService,
                                   radarState: radarState,
                                   cloudLayerState: cloudLayerState,
                                   modelGridState: modelGridState)
                    .padding(12)
                    Spacer()
                    mapControlStack
                        .padding(.trailing)
                        .padding(.top)
                }
                Spacer()
            }

            // Timeline chip — bottom, with the basemap credit tucked underneath
            VStack(spacing: 0) {
                Spacer()
                if settingsService.oscarRadarLayer {
                    OscarRadarTimelineControls(radarState: radarState,
                                               onBadgeTap: presentLayerPicker)
                        .padding(.horizontal, 16)
                } else if settingsService.cloudLayerActive {
                    CloudTimelineControls(cloudState: cloudLayerState,
                                          onBadgeTap: presentLayerPicker)
                        .padding(.horizontal, 16)
                } else if settingsService.activeTileLayer != nil {
                    WeatherTileTimelineControls(imageState: modelGridState,
                                                onBadgeTap: presentLayerPicker)
                        .padding(.horizontal, 16)
                }
                MapAttributionLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18)
                    .padding(.top, 5)
                    .padding(.bottom, 2)
            }
        }
        // Declared BEFORE the load task so the source pick lands first (both run
        // on the main actor and the pick has no suspension points).
        .task(id: "\(location.coordinates.latitude)|\(location.coordinates.longitude)") {
            // Capture knob: `-radarRegionLock brasil` pins the radar coverage
            // (used with `-mapInitialCenter` to screenshot the layer-picker
            // preview tiles), overriding the location-based pick.
            if let raw = UserDefaults.standard.string(forKey: "radarRegionLock"),
               let region = RadarRegion(rawValue: raw) {
                settingsService.activeTileLayer = nil
                settingsService.oscarRadarRegion = region
                settingsService.oscarRadarLayer = true
                return
            }
            settingsService.autoSelectRadarSource(
                latitude: location.coordinates.latitude,
                longitude: location.coordinates.longitude)
        }
        .task {
            // Cloud layer activation is settings-derived (not sync-derived: the
            // map coordinator's observation pass must stay read-only). Re-runs on
            // every return to the tab; setActive no-ops when unchanged.
            syncCloudActivation()
        }
        .task {
            // Re-runs on every return to the tab: full loads only the first time,
            // cheap staleness checks after that.
            if settingsService.oscarRadarLayer {
                radarState.setRegion(settingsService.oscarRadarRegion)
                if radarState.frames.isEmpty {
                    await radarState.loadAllFrames()
                } else {
                    await radarState.refreshIfStale()
                }
                // Testing hook: `-radarAutoPlay YES` starts playback immediately
                // (exercises sustained frame swaps without touch input).
                if UserDefaults.standard.bool(forKey: "radarAutoPlay") {
                    radarState.play()
                }
            } else if let layer = settingsService.activeTileLayer {
                if modelGridState.currentLayer == layer, modelGridState.hasAnyLoadedFrame {
                    await modelGridState.refreshIfStale()
                } else {
                    await modelGridState.loadLayer(layer)
                }
            }
        }
        .task {
            // The saved-city chips need the batch conditions even when the tab
            // opens before the locations list ever fetched them. Re-runs on
            // every return to the tab; the store throttles to one fetch per
            // 5 minutes.
            await CityConditionsStore.shared.refresh(
                coordinates: LocationService.shared.city.cities.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                }
            )
        }
        .task {
            // Map left open across server updates: re-fetch once metadata expires.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5 * 60))
                guard !Task.isCancelled else { break }
                await refreshActiveLayerIfStale()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from background: the timeline may be minutes to hours
            // old. refreshIfStale keeps a quick app switch free.
            guard phase == .active else { return }
            Task { await refreshActiveLayerIfStale() }
        }
        .onChange(of: settingsService.oscarRadarLayer) { _, isEnabled in
            if isEnabled {
                modelGridState.pause()
                radarState.setRegion(settingsService.oscarRadarRegion)
                if radarState.frames.isEmpty {
                    Task { await radarState.loadAllFrames() }
                }
            } else {
                radarState.pause()
            }
        }
        .onChange(of: settingsService.oscarRadarRegion) { _, newRegion in
            guard settingsService.oscarRadarLayer else { return }
            radarState.setRegion(newRegion)
            Task { await radarState.reloadForCurrentRegion() }
        }
        .onChange(of: settingsService.activeTileLayer) { _, newLayer in
            if let layer = newLayer {
                radarState.pause()
                Task { await modelGridState.loadLayer(layer) }
            } else {
                modelGridState.pause()
            }
        }
        .onDisappear {
            // Leaving the tab: stop playback; frames stay cached for the next visit.
            radarState.pause()
            modelGridState.pause()
            cloudLayerState.pause()
        }
        .sheet(isPresented: $isLayerPickerPresented) {
            MapLayerPickerSheet(
                settingsService: settingsService,
                onSelectRadar: { activate(radar: $0) },
                onSelectTileLayer: { activate(model: $0) },
                onSelectClouds: { activate() }
            )
            // No .presentationBackground override: iOS 26 renders the sheet as
            // Liquid Glass at the medium detent and swaps to an opaque background
            // when pulled up to .large.
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $tappedAlerts) { tapped in
            AlertInfoSheet(alerts: tapped.alerts)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $tappedCell) { cell in
            StormCellInfoSheet(
                cell: cell,
                referenceCoordinate: location.coordinates,
                referenceName: LocationService.shared.city.cities.first(where: \.selected)?.label
            )
            .presentationDetents([.medium])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationDragIndicator(.hidden)
        }
    }

    // MARK: - Map controls

    /// Apple-Maps-style control stack: the layer-picker entry point and the
    /// locate button share ONE glass capsule (user request — no separate
    /// floating circles). Locate flies the camera to the user's position
    /// (no-op without a fix/permission).
    private var mapControlStack: some View {
        VStack(spacing: 0) {
            Button(action: presentLayerPicker) {
                Image(systemName: "map.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 46, height: 46)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("Kartenebenen"))
            .accessibilityIdentifier("map.layerPicker")
            Divider()
                .frame(width: 26)
            Button {
                NotificationCenter.default.post(name: .mapCenterOnUser, object: nil)
            } label: {
                Image(systemName: "location")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("Auf meinen Standort zentrieren"))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Capsule())
    }

    private func presentLayerPicker() {
        isLayerPickerPresented = true
    }

    private func refreshActiveLayerIfStale() async {
        if settingsService.oscarRadarLayer {
            await radarState.refreshIfStale()
        } else if settingsService.cloudLayerActive {
            cloudLayerState.refreshIfStale()
        } else if settingsService.activeTileLayer != nil {
            await modelGridState.refreshIfStale()
        }
    }

    private func syncCloudActivation() {
        cloudLayerState.setActive(settingsService.cloudLayerActive)
    }

    /// Layer-picker selection: radar region, model layer, or (neither) the
    /// satellite clouds. The layers are mutually exclusive; the deselected
    /// ones pause, the selected one keeps its playback state.
    private func activate(radar: RadarRegion? = nil, model: WeatherTileLayer? = nil) {
        let clouds = radar == nil && model == nil
        settingsService.radarAutoFallbackActive = false
        if let radar { settingsService.oscarRadarRegion = radar } else { radarState.pause() }
        if model == nil { modelGridState.pause() }
        if !clouds { cloudLayerState.pause() }
        settingsService.oscarRadarLayer = radar != nil
        settingsService.activeTileLayer = model
        settingsService.cloudLayerActive = clouds
        syncCloudActivation()
    }
}

// MARK: - Legend stack

/// Own view so the per-tick `currentFrameTimestamp` reads invalidate only this
/// stack, not the whole fullscreen map body.
private struct MapLegendStack: View {
    let settingsService: SettingService
    let radarState: OscarRadarState
    let cloudLayerState: CloudLayerState
    let modelGridState: ModelGridLayerState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settingsService.oscarRadarLayer {
                if radarState.hasAnyLoadedFrame,
                   let timestamp = radarState.currentFrameTimestamp {
                    RadarTimestampBadge(
                        timestamp: timestamp,
                        isLive: radarState.isCurrentFrameLive
                    )
                    ColormapVerticalLegend(colormap: .radar)
                }
                if settingsService.showStormCells {
                    StormCellLegend()
                }
            } else if settingsService.cloudLayerActive,
                      cloudLayerState.hasAnyLoadedFrame {
                if cloudLayerState.frameTimestamps.indices.contains(cloudLayerState.currentFrameIndex) {
                    RadarTimestampBadge(
                        timestamp: cloudLayerState.frameTimestamps[cloudLayerState.currentFrameIndex],
                        isLive: cloudLayerState.isCurrentFrameLive
                    )
                }
            } else if settingsService.activeTileLayer != nil,
                      modelGridState.hasAnyLoadedFrame {
                if let timestamp = modelGridState.currentFrameTimestamp {
                    RadarTimestampBadge(timestamp: timestamp, isLive: false)
                }
                if let colormap = settingsService.activeTileLayer?.colormap {
                    ColormapVerticalLegend(colormap: colormap)
                }
            }
        }
    }
}
