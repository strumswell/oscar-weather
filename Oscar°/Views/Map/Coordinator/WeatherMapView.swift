//
//  WeatherMapView.swift
//  Oscar°
//
//  THE weather map (MapLibre Native). Replaces the former MapKit map entirely.
//
//  Radar renders INSIDE MapLibre's render loop as an `MLNCustomStyleLayer`: zero
//  basemap skew by construction, below the place labels, r8 value-grid textures +
//  palette LUT in the fragment shader. No RGBA frame images anywhere (an earlier
//  MLNImageSource attempt re-uploaded a full RGBA frame per scrub step and got the
//  app jetsam-killed while scrubbing OPERA).
//
//  Playback morphs between frames along the server's per-pair motion fields
//  (`/radar/{region}/motion`, two-sided backward warp — the Dark Sky technique), so
//  rain slides in its real direction instead of cross-dissolving. The layer picker's
//  "Flüssige Bewegungen" toggle and the system Reduce Motion setting fall back to
//  exact frames.
//
//  Other layers: radar motion arrows (client-side symbol layer), ICON-D2/ECMWF
//  model grids and satellite clouds (custom layers), wind particles (sibling CPU
//  overlay view), city chips, storm cells, isobars, warning polygons, user location.
//
//  Basemap: OpenFreeMap (no API key). MapLibre's own attribution control is hidden;
//  MapAttributionLabel carries the OpenFreeMap/OSM (ODbL) credit.
//

import CoreLocation
import MapLibre
import Metal
import OSLog
import Observation
import SwiftUI
import UIKit

let weatherMapLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "WeatherMap")

// MARK: - Map view (representable)

struct MapLayerOverride: Equatable {
    var radar: Bool
    var tileLayer: WeatherTileLayer?
}

struct WeatherMapView: UIViewRepresentable {
    let settingsService: SettingService
    var coordinates: CLLocationCoordinate2D
    var cities: [City]
    var overlayOpacity: Double
    var oscarRadarState: OscarRadarState?
    var modelGridState: ModelGridLayerState?
    var cloudLayerState: CloudLayerState?
    var combinedTimeline: CombinedTimelineState? = nil
    var onAlertsTapped: (([WeatherAlertInfo]) -> Void)? = nil
    var onCellTapped: ((StormCellInfo) -> Void)? = nil
    var onWebcamTapped: ((Components.Schemas.Webcam) -> Void)? = nil
    var layerOverride: MapLayerOverride? = nil
    var startZoom: Double? = nil

    static let radarLayerID = "oscar-radar-layer"
    static let modelLayerID = "oscar-model-image"
    static let cloudsLayerID = "oscar-clouds-layer"
    static let alertSourceCount = 8
    static func alertSourceID(_ index: Int) -> String { "oscar-alert-polygons-\(index)" }
    static func alertFillLayerID(_ index: Int) -> String { "oscar-alert-fill-\(index)" }
    static func alertOutlineLayerID(_ index: Int) -> String { "oscar-alert-outline-\(index)" }
    static var alertFillLayerIDs: Set<String> {
        Set((0..<alertSourceCount).map(alertFillLayerID))
    }
    static let isobarBufferCount = 2
    static func isobarSourceID(_ buffer: Int) -> String { "oscar-isobar-source-\(buffer)" }
    static func isobarCasingLayerID(_ buffer: Int) -> String { "oscar-isobar-casing-\(buffer)" }
    static func isobarLineLayerID(_ buffer: Int) -> String { "oscar-isobar-line-\(buffer)" }
    static func isobarLabelLayerID(_ buffer: Int) -> String { "oscar-isobar-label-\(buffer)" }
    static func isobarCenterLayerID(_ buffer: Int) -> String { "oscar-isobar-center-\(buffer)" }
    static func isobarCenterValueLayerID(_ buffer: Int) -> String { "oscar-isobar-center-value-\(buffer)" }
    static let cellPointSourceID = "oscar-cells-points"
    static let cellTrackSourceID = "oscar-cells-tracks"
    static let cellConeSourceID = "oscar-cells-cones"
    static let cellFootprintSourceID = "oscar-cells-footprints"
    static let cellTickSourceID = "oscar-cells-ticks"
    static let cellHeadSourceID = "oscar-cells-heads"
    static let cellCircleLayerID = "oscar-cells-circle"
    static let cellTrackLayerID = "oscar-cells-track"
    static let cellConeLayerID = "oscar-cells-cone"
    static let cellFootprintFillLayerID = "oscar-cells-footprint-fill"
    static let cellFootprintLineLayerID = "oscar-cells-footprint-line"
    static let cellTickLayerID = "oscar-cells-tick"
    static let cellTickLabelLayerID = "oscar-cells-tick-label"
    static let cellHeadLayerID = "oscar-cells-head"
    static let cellArrowImageName = "oscar-cell-arrow"
    static let webcamSourceID = "oscar-webcams"
    static let webcamLayerID = "oscar-webcams-layer"

    private static var initialZoom: Double {
        let override = UserDefaults.standard.double(forKey: "mapInitialZoom")
        return override > 0 ? override : 7
    }

    private static var initialCenterOverride: CLLocationCoordinate2D? {
        guard let raw = UserDefaults.standard.string(forKey: "mapInitialCenter") else { return nil }
        let parts = raw.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1])
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: settingsService.mapBasemapStyle.styleURL)
        weatherMapLogger.info("map view created")
        mapView.delegate = context.coordinator
        mapView.setCenter(Self.initialCenterOverride ?? coordinates,
                          zoomLevel: startZoom ?? Self.initialZoom, animated: false)
        mapView.allowsTilting = false
        mapView.showsUserLocation = Self.locationAuthorized
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true
        mapView.compassView.compassVisibility = .adaptive
        mapView.compassViewPosition = .topRight
        mapView.compassViewMargins = Self.compassMargins(radarControls: false)

        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        for recognizer in mapView.gestureRecognizers ?? []
        where recognizer is UITapGestureRecognizer {
            tap.require(toFail: recognizer)
        }
        mapView.addGestureRecognizer(tap)

        let particleView = WindParticleView(frame: mapView.bounds)
        particleView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        particleView.mapView = mapView
        particleView.isHidden = true
        mapView.addSubview(particleView)
        context.coordinator.windParticleView = particleView

        context.coordinator.mapView = mapView
        context.coordinator.startObservingAppState()
        return mapView
    }

    static func compassMargins(radarControls: Bool) -> CGPoint {
        CGPoint(x: 19, y: radarControls ? 273 : 168)
    }

    @MainActor static var locationAuthorized: Bool {
        switch LocationService.shared.authStatus {
        case .authorizedWhenInUse, .authorizedAlways: true
        default: false
        }
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncAll()
        context.coordinator.recenterIfPlaceChanged()

        let authorized = Self.locationAuthorized
        if mapView.showsUserLocation != authorized {
            mapView.showsUserLocation = authorized
        }
    }

    static func dismantleUIView(_ mapView: MLNMapView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var parent: WeatherMapView
        weak var mapView: MLNMapView?
        weak var windParticleView: WindParticleView?

        var radarLayer: RadarCustomStyleLayer?
        var lastFrameKey: String?
        var lastRenderIndex = -1
        var lastBounds: OscarRadarBounds?
        var radarPaletteId: String?
        var isFetchingPalette = false
        private var lastBlockReason: String?

        var arrowSourceID: String?

        let handoverSweep = MapHandoverSweep()
        var lastShowsModelPart: Bool?

        var modelLayer: RadarCustomStyleLayer?
        var modelPaletteId: String?
        var modelPalette: [PixelRGBA]?
        var lastModelFrameKey: String?
        var lastModelBounds: OscarRadarBounds?

        var cloudsLayer: RadarCustomStyleLayer?
        var cloudsPalette: [PixelRGBA]?
        var cloudsPaletteFetching = false
        var lastCloudsPairKey: String?
        var lastCloudsBounds: OscarRadarBounds?

        var bubbleSyncKey: String?
        var lastBubbleSignature: String?
        var registeredBubbleIcons: Set<String> = []

        var alertOverlayData: Data?
        var alertOverlayFetchedAt: Date?
        var alertOverlayBox: AlertFetchBox?

        var isLoadingAlertOverlay = false

        var stormCells: [StormCellInfo]?
        var stormCellsFetchedAt: Date?
        var stormCellsRegion: RadarRegion?
        var isLoadingStormCells = false

        var webcams: [Components.Schemas.Webcam] = []
        var webcamMarkers: [Int: UIImage] = [:]
        var webcamBox: WebcamBox?
        var webcamsFetchedAt: Date?
        var isLoadingWebcams = false

        var isobarShapes: [String: MLNShape] = [:]
        var isobarFetchesInFlight: Set<String> = []
        var isobarFailures: [String: Date] = [:]
        var isobarSyncKey: String?
        var isobarActiveBuffer = 0
        var isobarCleanupGeneration = 0


        var selectedCityMarkerIdentity: String?

        var cityChipSignature: String?
        var registeredCityChipImages: Set<String> = []

        var lastWindFrameKey: String?

        var isTornDown = false
        nonisolated(unsafe) private var reduceMotionObserver: NSObjectProtocol?
        nonisolated(unsafe) private var centerOnUserObserver: NSObjectProtocol?
        nonisolated(unsafe) private var interactionEndWorkItem: DispatchWorkItem?
        nonisolated(unsafe) var userDotPulseTimer: Timer?
        private var isMapInteractionActive = false
        private var centeredCoordinates: CLLocationCoordinate2D

        init(_ parent: WeatherMapView) {
            self.parent = parent
            centeredCoordinates = parent.coordinates
            super.init()
            reduceMotionObserver = NotificationCenter.default.addObserver(
                forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncAll() }
            }
            centerOnUserObserver = NotificationCenter.default.addObserver(
                forName: .mapCenterOnUser, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.centerOnUserLocation() }
            }
        }

        deinit {
            interactionEndWorkItem?.cancel()
            userDotPulseTimer?.invalidate()
            if let reduceMotionObserver {
                NotificationCenter.default.removeObserver(reduceMotionObserver)
            }
            if let centerOnUserObserver {
                NotificationCenter.default.removeObserver(centerOnUserObserver)
            }
        }

        private func centerOnUserLocation() {
            guard let mapView,
                  let coordinate = LocationService.shared.getGPSCoordinates(),
                  CLLocationCoordinate2DIsValid(coordinate) else { return }
            mapView.setCenter(coordinate, zoomLevel: max(mapView.zoomLevel, 9), animated: true)
        }

        func recenterIfPlaceChanged() {
            let target = parent.coordinates
            let moved = CLLocation(latitude: target.latitude, longitude: target.longitude)
                .distance(from: CLLocation(latitude: centeredCoordinates.latitude, longitude: centeredCoordinates.longitude))
            guard moved > 2_000, WeatherMapView.initialCenterOverride == nil, let mapView else { return }
            centeredCoordinates = target
            mapView.setCenter(target, animated: false)
        }

        func tearDown() {
            isTornDown = true
            radarLayer?.stopPlayback()
            radarLayer?.purgeTextures()
            modelLayer?.stopPlayback()
            modelLayer?.purgeTextures()
            cloudsLayer?.purgeTextures()
            handoverSweep.stop()
            userDotPulseTimer?.invalidate()
            userDotPulseTimer = nil
        }

        func blocked(_ reason: String?) {
            guard lastBlockReason != reason else { return }
            lastBlockReason = reason
            if let reason {
                weatherMapLogger.info("sync blocked: \(reason, privacy: .public)")
            }
        }

        func startObservingAppState() {
            guard !isTornDown else { return }
            withObservationTracking { [weak self] in
                self?.syncAll()
            } onChange: { [weak self] in
                Task { @MainActor in
                    self?.startObservingAppState()
                }
            }
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            weatherMapLogger.info("style loaded")
            radarLayer?.stopPlayback()
            radarLayer?.purgeTextures()
            radarLayer = nil
            lastFrameKey = nil
            lastRenderIndex = -1
            lastBounds = nil
            radarPaletteId = nil
            modelLayer?.stopPlayback()
            modelLayer?.purgeTextures()
            modelLayer = nil
            modelPaletteId = nil
            modelPalette = nil
            lastModelFrameKey = nil
            lastModelBounds = nil
            // Palette cache survives (id never changes); the layer handle must not.
            cloudsLayer?.purgeTextures()
            cloudsLayer = nil
            lastCloudsPairKey = nil
            lastCloudsBounds = nil
            arrowSourceID = nil
            bubbleSyncKey = nil
            lastBubbleSignature = nil
            registeredBubbleIcons.removeAll()
            isobarSyncKey = nil
            isobarActiveBuffer = 0
            cityChipSignature = nil
            registeredCityChipImages.removeAll()
            selectedCityMarkerIdentity = nil
            syncAll()
        }

        // MARK: Interaction plumbing (pauses prefetch during gestures, like MapKit did)

        func mapView(_ mapView: MLNMapView, regionWillChangeAnimated animated: Bool) {
            interactionEndWorkItem?.cancel()
            interactionEndWorkItem = nil
            guard !isMapInteractionActive else { return }
            isMapInteractionActive = true
            parent.oscarRadarState?.beginMapInteraction()
            parent.modelGridState?.beginMapInteraction()
            parent.cloudLayerState?.beginMapInteraction()
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            windParticleView?.onMapRegionChanged()
            interactionEndWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.isMapInteractionActive {
                    self.isMapInteractionActive = false
                    self.parent.oscarRadarState?.endMapInteraction()
                    self.parent.modelGridState?.endMapInteraction()
                    self.parent.cloudLayerState?.endMapInteraction()
                }
                self.syncAll()
            }
            interactionEndWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
        }

        // MARK: Sync (single entry point; reads register observation dependencies)

        func syncAll() {
            guard !isTornDown else { return }
            let settings = parent.settingsService
            let fixedLayers = parent.layerOverride
            let usesSettings = fixedLayers == nil
            let radarActive = fixedLayers?.radar ?? settings.oscarRadarLayer
            let smoothMotion = settings.radarSmoothMotion
            let softRendering = settings.radarSoftRendering
            let motionArrows = settings.radarMotionArrows
            let valueBubbles = settings.mapValueBubbles
            let activeTileLayer = usesSettings ? settings.activeTileLayer : fixedLayers?.tileLayer
            let alertPolygons = usesSettings && settings.showAlertPolygons
            let stormCells = usesSettings && settings.showStormCells
            let isobars = (usesSettings && settings.showIsobars) || activeTileLayer?.isPressureLayer == true
            let radarRegion = settings.oscarRadarRegion
            let webcamsOn = usesSettings && settings.mapWebcams
            _ = settings.mapOverlayOpacity
            let basemapStyle = settings.mapBasemapStyle

            let radarState = parent.oscarRadarState
            let radarBounds = radarState?.bounds
            let radarFrame = radarState?.currentFrame
            let radarRenderedIndex = radarState?.renderFrameIndex ?? radarState?.currentFrameIndex ?? 0
            let radarLoadedCount = radarState?.loadedFrameIndices.count ?? 0
            let radarFrameCount = radarState?.frames.count ?? 0
            let radarIsPlaying = radarState?.isPlaying ?? false
            let radarMotion = radarState?.motion

            let continuation = parent.combinedTimeline
            let continuationActive = radarActive && (continuation?.includesModel ?? false)
            let showsModelPart = radarActive && (continuation?.isShowingModel ?? false)
            let radarPlayer: (any TimelinePlayerState)? = continuation != nil ? continuation : radarState
            let radarAtEnd = radarRenderedIndex == radarFrameCount - 1
            let radarNext = continuationActive && radarAtEnd ? nil : radarState?.nextFrame

            let cloudsActive = usesSettings && settings.cloudLayerActive
            let cloudState = parent.cloudLayerState
            let cloudBounds = cloudState?.bounds
            let cloudMotion = cloudState?.motion
            let cloudIsPlaying = cloudState?.isPlaying ?? false
            _ = cloudState?.loadRevision
            _ = cloudState?.isActive
            _ = cloudState?.currentFrameIndex
            _ = cloudState?.renderFrameIndex

            let modelState = parent.modelGridState
            let modelBounds = modelState?.bounds
            let modelFrame = modelState?.currentFrame
            let modelFrameKey = modelState?.currentFrameKey
            let modelAtEnd = modelState.map {
                ($0.renderFrameIndex ?? $0.currentFrameIndex) == $0.frameTimestamps.count - 1
            } ?? false
            let modelNext = continuationActive && modelAtEnd ? nil : modelState?.nextFrameKeyed
            let modelPlayer: (any TimelinePlayerState)? = continuationActive ? continuation : modelState
            let modelIsPlaying = modelState?.isPlaying ?? false
            let modelMotion = modelState?.motion
            _ = modelState?.currentLayer
            _ = modelState?.renderFrameIndex
            _ = modelState?.currentFrameIndex

            if let mapView, mapView.styleURL != basemapStyle.styleURL {
                mapView.styleURL = basemapStyle.styleURL
                return blocked("style reloading")
            }

            guard let style = mapView?.style else { return blocked("style not loaded") }
            blocked(nil)

            let compassMargins = WeatherMapView.compassMargins(radarControls: radarActive && continuation != nil)
            if let mapView, mapView.compassViewMargins != compassMargins {
                mapView.compassViewMargins = compassMargins
            }

            syncHandover(radarActive: radarActive, showsModelPart: showsModelPart,
                         isPlaying: continuation?.isPlaying ?? false)
            let sweeping = handoverSweep.isRunning

            syncClouds(style: style, active: cloudsActive, state: cloudState,
                       bounds: cloudBounds, motion: cloudMotion,
                       cloudIsPlaying: cloudIsPlaying, smoothMotion: smoothMotion)
            syncRadar(style: style, active: radarActive, state: radarState,
                      bounds: radarBounds,
                      frame: radarFrame, next: radarNext, renderedIndex: radarRenderedIndex,
                      loadedCount: radarLoadedCount, frameCount: radarFrameCount,
                      isPlaying: radarIsPlaying, motion: radarMotion, smoothMotion: smoothMotion,
                      softRendering: softRendering, arrowsEnabled: motionArrows && !showsModelPart,
                      visible: !showsModelPart || sweeping, player: radarPlayer)
            syncModelLayer(style: style,
                           selection: activeTileLayer ?? (continuationActive ? modelState?.currentLayer : nil),
                           visible: activeTileLayer != nil || showsModelPart || sweeping, state: modelState,
                           bounds: modelBounds, payload: modelFrame, frameKey: modelFrameKey,
                           next: modelNext, isPlaying: modelIsPlaying, motion: modelMotion,
                           smoothMotion: smoothMotion, softRendering: softRendering, player: modelPlayer)
            syncValueBubbles(style: style, selection: activeTileLayer, enabled: valueBubbles,
                             payload: modelFrame, frameKey: modelFrameKey)
            syncIsobars(style: style, active: isobars && activeTileLayer != nil,
                        selection: activeTileLayer, frameKey: modelFrameKey)
            syncAlertPolygons(style: style, active: alertPolygons)
            syncStormCells(style: style, active: stormCells && radarActive && !showsModelPart,
                           region: radarRegion)
            syncWindParticles(selection: activeTileLayer, state: modelState)
            syncWebcams(style: style, active: webcamsOn && parent.onWebcamTapped != nil)
            syncUserLocationDot(style: style)
            syncCityChips(style: style)
            syncSelectedCityMarker(style: style)
        }

        var syncRetryScheduled = false
        func scheduleSyncRetry() {
            guard !syncRetryScheduled else { return }
            syncRetryScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                self.syncRetryScheduled = false
                self.syncAll()
            }
        }

        // MARK: Helpers

        func insertOverlayLayer(_ layer: MLNStyleLayer, in style: MLNStyle) {
            let dotLayerIDs = [UserLocationDot.haloLayerID, UserLocationDot.pulseLayerID, UserLocationDot.dotLayerID]
            if let lastGeometry = style.layers.last(where: {
                !($0 is MLNSymbolStyleLayer) && !dotLayerIDs.contains($0.identifier)
            }) {
                style.insertLayer(layer, above: lastGeometry)
            } else {
                style.addLayer(layer)
            }
        }

        func recenterIntoRadarBoundsIfNeeded(animated: Bool) {
            guard let mapView, let bounds = parent.oscarRadarState?.bounds,
                  parent.settingsService.oscarRadarLayer else { return }
            let center = mapView.centerCoordinate
            let inside = center.latitude <= bounds.north && center.latitude >= bounds.south
                && center.longitude >= bounds.west && center.longitude <= bounds.east
            guard !inside else { return }
            let regionCenter = CLLocationCoordinate2D(
                latitude: (bounds.north + bounds.south) / 2,
                longitude: (bounds.west + bounds.east) / 2)
            let lonSpan = max(1, bounds.east - bounds.west)
            let zoom = max(2.5, log2(360.0 / lonSpan) + 0.5)
            mapView.setCenter(regionCenter, zoomLevel: zoom, animated: animated)
        }
    }
}

extension MLNStyle {
    func removeLayers(withIdentifiers ids: [String]) {
        for id in ids {
            if let layer = layer(withIdentifier: id) { removeLayer(layer) }
        }
    }

    func removeSources(withIdentifiers ids: [String]) {
        for id in ids {
            if let source = source(withIdentifier: id) { removeSource(source) }
        }
    }
}

extension WeatherMapView.Coordinator {
    func syncPlayback(of layer: RadarCustomStyleLayer, state: any TimelinePlayerState,
                      playing: Bool, interval: TimeInterval, interpolate: Bool) {
        if playing {
            state.cancelInternalTimer()
            layer.startPlayback(interval: interval, interpolate: interpolate) { [weak state] in
                state?.advanceFrame()
            }
        } else if layer.isPlaybackActive {
            layer.stopPlayback()
        }
    }
}
