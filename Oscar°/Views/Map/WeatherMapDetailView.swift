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
    /// iOS 6 bars instead of the glass chrome (the classic theme's map),
    /// closed through `onDone`. Loading and layer switching are the same.
    var classicChrome = false
    var onDone: () -> Void = {}
    @Environment(Location.self) private var location: Location
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var layers = MapLayers()
    @State private var isLayerPickerPresented = false
    // sheet(item:), not sheet(isPresented:) + separate array state: the isPresented
    // variant renders its content once with the PRE-tap (empty) array on the first
    // presentation — the classic stale-state sheet bug.
    @State private var tappedAlerts: TappedAlerts?
    @State private var tappedCell: StormCellInfo?
    @State private var tappedWebcam: Components.Schemas.Webcam?
    @Namespace private var controlsNamespace

    private var timeline: CombinedTimelineState { layers.timeline }
    private var cloudLayerState: CloudLayerState { layers.clouds }
    private var radarState: OscarRadarState { layers.radar }
    private var modelGridState: ModelGridLayerState { layers.model }

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
                combinedTimeline: classicChrome ? nil : timeline,
                onAlertsTapped: { alerts in
                    tappedAlerts = TappedAlerts(alerts: alerts)
                },
                onCellTapped: { cell in
                    tappedCell = cell
                },
                onWebcamTapped: { webcam in
                    tappedWebcam = webcam
                }
            )
            .ignoresSafeArea()

            if classicChrome {
                ClassicMapChrome(
                    settingsService: settingsService,
                    radarState: radarState,
                    modelGridState: modelGridState,
                    cloudLayerState: cloudLayerState,
                    onSelectRadar: { activate(radar: $0) },
                    onSelectTileLayer: { activate(model: $0) },
                    onSelectClouds: { activate() },
                    onDone: onDone
                )
            } else {
            // Timestamp badge + legend — top-left. The badge doubles as the
            // scrub readout: eyes travel up from the scrubber to read the time
            // here, so it stays even though the chip header shows it too.
            VStack {
                HStack(alignment: .top) {
                    MapLegendStack(settingsService: settingsService,
                                   timeline: timeline,
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
                Group {
                    if settingsService.oscarRadarLayer {
                        OscarRadarTimelineControls(timeline: timeline,
                                                   onBadgeTap: presentLayerPicker)
                    } else if settingsService.cloudLayerActive {
                        CloudTimelineControls(cloudState: cloudLayerState,
                                              onBadgeTap: presentLayerPicker)
                    } else if settingsService.activeTileLayer != nil {
                        WeatherTileTimelineControls(imageState: modelGridState,
                                                    onBadgeTap: presentLayerPicker)
                    }
                }
                .padding(.horizontal, 16)
                // Phone width on iPad and Mac: a window-wide scrubber is a long reach.
                .frame(maxWidth: 640)
                MapAttributionLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18)
                    .padding(.top, 5)
                    .padding(.bottom, 2)
            }
            }
        }
        // Declared BEFORE the load task so the source pick lands first (both run
        // on the main actor and the pick has no suspension points).
        .task(id: "\(location.coordinates.latitude)|\(location.coordinates.longitude)") {
            layers.pickRadarSource(for: location.coordinates)
        }
        .task {
            // Cloud layer activation is settings-derived (not sync-derived: the
            // map coordinator's observation pass must stay read-only). Re-runs on
            // every return to the tab.
            layers.syncCloudActivation()
        }
        .task {
            // Re-runs on every return to the tab.
            await layers.loadActiveLayer()
            // Testing hook: `-radarAutoPlay YES` starts playback immediately
            // (exercises sustained frame swaps without touch input).
            if settingsService.oscarRadarLayer, UserDefaults.standard.bool(forKey: "radarAutoPlay") {
                radarState.play()
            }
        }
        .task(id: continuation) {
            await layers.loadContinuation(continuation)
        }
        .task {
            await layers.refreshCityChips()
        }
        .task {
            await layers.keepFresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from background: the timeline may be minutes to hours
            // old. refreshIfStale keeps a quick app switch free.
            guard phase == .active else { return }
            Task { await layers.refreshIfStale() }
        }
        .onChange(of: settingsService.oscarRadarLayer) { _, isEnabled in
            if isEnabled {
                modelGridState.pause()
                timeline.currentFrameIndex = radarState.currentFrameIndex
                radarState.setRegion(settingsService.oscarRadarRegion)
                if radarState.frames.isEmpty {
                    Task { await radarState.loadAllFrames() }
                }
            } else {
                radarState.pause()
            }
        }
        .onChange(of: settingsService.radarModelContinuation) { _, isOn in
            if !isOn { modelGridState.pause() }
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
            layers.pause()
        }
        // A sheet on iPhone, a trailing column next to the map on wider windows.
        .inspector(isPresented: $isLayerPickerPresented) {
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
            .inspectorColumnWidth(min: 320, ideal: 360, max: 420)
        }
        // In a regular-width window the inspector wraps the map in a column
        // container that stops below the status bar (a black strip); let that
        // container reach the top. Compact widths get a sheet, no container.
        .ignoresSafeArea(edges: horizontalSizeClass == .regular ? .top : [])
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
        .sheet(item: $tappedWebcam) { webcam in
            WebcamSheet(webcam: webcam, timeZone: .current)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    /// The classic map has no continuation chip, so it never loads one.
    private var continuation: MapLayers.Continuation? {
        classicChrome ? nil : layers.continuation
    }

    // MARK: - Map controls

    /// Apple-Maps-style control stack: the layer-picker entry point, the
    /// locate button and the webcam toggle share ONE glass capsule (user request — no separate
    /// floating circles). Locate flies the camera to the user's position
    /// (no-op without a fix/permission). The radar's own toggles sit in a second
    /// capsule below, which melts out of the first when radar is picked.
    private var mapControlStack: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                mainControls
                    .glassEffectID("main", in: controlsNamespace)
                if settingsService.oscarRadarLayer {
                    radarControls
                        .glassEffectID("radar", in: controlsNamespace)
                }
            }
        }
        .animation(.smooth(duration: 0.35), value: settingsService.oscarRadarLayer)
    }

    private var mainControls: some View {
        @Bindable var settings = settingsService
        return VStack(spacing: 0) {
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
            Divider()
                .frame(width: 26)
            Toggle(isOn: $settings.mapWebcams) {
                Image(systemName: "web.camera")
                    .font(.system(size: 17, weight: .semibold))
                    .modifier(SlashedWhenOff(isOn: settingsService.mapWebcams))
            }
            .toggleStyle(MapControlToggleStyle())
            .accessibilityLabel(Text("Webcams"))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Capsule())
    }

    /// On/off reads as a slash through the control, like the system's `.slash` symbols.
    private var radarControls: some View {
        @Bindable var settings = settingsService
        let model = settingsService.oscarRadarRegion.continuationLayer
        return VStack(spacing: 0) {
            Toggle(isOn: $settings.radarMotionArrows) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 17, weight: .semibold))
                    .modifier(SlashedWhenOff(isOn: settingsService.radarMotionArrows))
            }
            .accessibilityLabel(Text("Bewegungspfeile"))
            Divider()
                .frame(width: 26)
            Toggle(isOn: $settings.radarModelContinuation) {
                Text("+\(model.horizonHours)h")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .modifier(SlashedWhenOff(isOn: settingsService.radarModelContinuation))
            }
            .accessibilityLabel(Text("Mit \(model.shortSourceLabel) fortsetzen"))
        }
        .toggleStyle(MapControlToggleStyle())
        .glassEffect(.regular, in: Capsule())
    }

    private func presentLayerPicker() {
        isLayerPickerPresented = true
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
        layers.syncCloudActivation()
    }
}

// MARK: - Radar control toggles

/// A bare 46 pt tap target for the control capsule; state shows in the label.
private struct MapControlToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .frame(width: 46, height: 46)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

/// The system `.slash` look for glyphs that have no slash variant: a thin
/// glyph-sized stroke with a knockout gap cut into the content around it.
private struct SlashedWhenOff: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        content
            .mask {
                Rectangle()
                    .overlay { slash(lineWidth: 5).blendMode(.destinationOut) }
                    .compositingGroup()
            }
            .overlay { slash(lineWidth: 1.7) }
            .animation(.smooth(duration: 0.25), value: isOn)
    }

    private func slash(lineWidth: CGFloat) -> some View {
        SlashLine()
            .trim(from: 0, to: isOn ? 0 : 1)
            .stroke(.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: 18, height: 18)
    }
}

private struct SlashLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    }
}

// MARK: - Legend stack

/// Own view so the per-tick `currentFrameTimestamp` reads invalidate only this
/// stack, not the whole map body. Shared by the Karten tab and the forecast's
/// map preview.
struct MapLegendStack: View {
    let settingsService: SettingService
    let timeline: CombinedTimelineState
    let cloudLayerState: CloudLayerState
    let modelGridState: ModelGridLayerState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settingsService.oscarRadarLayer {
                if timeline.hasAnyLoadedFrame,
                   let timestamp = timeline.currentFrameTimestamp {
                    RadarTimestampBadge(
                        timestamp: timestamp,
                        isLive: timeline.isCurrentFrameLive
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
