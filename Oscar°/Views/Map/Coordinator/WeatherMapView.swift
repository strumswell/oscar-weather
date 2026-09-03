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

struct WeatherMapView: UIViewRepresentable {
    let settingsService: SettingService
    var coordinates: CLLocationCoordinate2D
    var cities: [City]
    var overlayOpacity: Double
    var showWindParticles: Bool
    var oscarRadarState: OscarRadarState?
    var modelGridState: ModelGridLayerState?
    var cloudLayerState: CloudLayerState?
    /// Tap on warning polygon(s) → all warnings under the finger, most severe first.
    var onAlertsTapped: (([WeatherAlertInfo]) -> Void)? = nil
    /// Tap on a storm-cell marker/footprint → that cell's details.
    var onCellTapped: ((StormCellInfo) -> Void)? = nil

    static let radarLayerID = "oscar-radar-layer"
    static let modelLayerID = "oscar-model-image"
    static let cloudsLayerID = "oscar-clouds-layer"
    // The warning overlay is SPLIT across several sources: MapLibre silently
    // stops rendering features once one source's tile bucket packs too many
    // vertices (a dense Meteoalarm viewport dropped whole department outlines,
    // leaving stray fragments) — round-robin distribution keeps every bucket
    // far below that threshold at full geometry fidelity. Eight sources put a
    // ~30k-vertex continental viewport at ~4k per source, the empirically
    // clean range (4 sources @ ~7k still dropped features).
    static let alertSourceCount = 8
    static func alertSourceID(_ index: Int) -> String { "oscar-alert-polygons-\(index)" }
    static func alertFillLayerID(_ index: Int) -> String { "oscar-alert-fill-\(index)" }
    static func alertOutlineLayerID(_ index: Int) -> String { "oscar-alert-outline-\(index)" }
    static var alertFillLayerIDs: Set<String> {
        Set((0..<alertSourceCount).map(alertFillLayerID))
    }
    // Isobars are double-buffered (two sources + layer sets): a frame change
    // loads the hidden buffer and cross-fades, instead of hard-swapping GeoJSON.
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

    /// Initial camera zoom, overridable via `-mapInitialZoom <z>` (UserDefaults
    /// argument domain or persisted default) — a dev/staging knob like
    /// `-radarBaseURL`, unset in every normal launch.
    private static var initialZoom: Double {
        let override = UserDefaults.standard.double(forKey: "mapInitialZoom")
        return override > 0 ? override : 7
    }

    /// Initial camera center, overridable via `-mapInitialCenter "@lat,lon"` —
    /// a capture knob (layer-picker preview tiles are screenshot at a fixed
    /// spot regardless of the selected city), unset in every normal launch.
    /// The `@` prefix keeps a negative latitude from being parsed as the next
    /// launch-argument key.
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
        // OpenFreeMap basemap (no API key), user-selectable style — Fiord default.
        let mapView = MLNMapView(frame: .zero, styleURL: settingsService.mapBasemapStyle.styleURL)
        weatherMapLogger.info("map view created")
        mapView.delegate = context.coordinator
        mapView.setCenter(Self.initialCenterOverride ?? coordinates,
                          zoomLevel: Self.initialZoom, animated: false)
        mapView.allowsTilting = false
        // MapLibre requests location permission itself the moment this is enabled
        // while the status is undetermined, so show the user dot only once access
        // already exists; updateUIView turns it on after a grant.
        mapView.showsUserLocation = Self.locationAuthorized
        // OpenFreeMap/OSM (ODbL) attribution is an always-visible corner label
        // (MapAttributionLabel, drawn by the SwiftUI host) — the OSMF-preferred
        // form — so MapLibre's ⓘ button and wordmark both stay hidden.
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true
        // Compass: adaptive — appears only while the map is rotated off north,
        // tap resets. Seated below the SwiftUI control capsule that owns the
        // top-right corner (16pt top padding + two 46pt buttons + divider) and
        // centered on its 46pt width (the compass image is 40pt). Margins are
        // safe-area-relative, matching the SwiftUI overlay's frame.
        mapView.compassView.compassVisibility = .adaptive
        mapView.compassViewPosition = .topRight
        mapView.compassViewMargins = CGPoint(x: 19, y: 121)

        // Feature tap-through: warnings + storm cells. The map's own tap
        // recognizers must fail first (annotation selection, double-tap zoom) —
        // the standard MapLibre feature-query pattern.
        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        for recognizer in mapView.gestureRecognizers ?? []
        where recognizer is UITapGestureRecognizer {
            tap.require(toFail: recognizer)
        }
        mapView.addGestureRecognizer(tap)

        // Wind particle overlay: a sibling view ABOVE the map (its content is
        // re-seeded on region changes; particles need no per-frame map sync).
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

    /// True only when location access has already been granted — never triggers a
    /// prompt, so the map's user-location dot cannot raise the system dialog
    /// before the onboarding step does.
    @MainActor static var locationAuthorized: Bool {
        switch LocationService.shared.authStatus {
        case .authorizedWhenInUse, .authorizedAlways: true
        default: false
        }
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncAll()

        // Enable the user-location dot once access is granted (e.g. after the
        // onboarding location step), without recreating the map.
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

        // Per-frame isobar GeoJSON, keyed "framesEndpoint/frameKey" (see syncIsobars).
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

        init(_ parent: WeatherMapView) {
            self.parent = parent
            super.init()
            reduceMotionObserver = NotificationCenter.default.addObserver(
                forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncAll() }
            }
            // Camera command from the locate button.
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

        /// Locate button: fly to the user's position. Reads the app's own
        /// location service (CLLocationManager's last fix) — MapLibre's
        /// `userLocation` stays empty until ITS internal manager delivers one,
        /// which made the button a silent no-op. Zooms in when the camera is
        /// wide, keeps the user's closer zoom otherwise. Still a no-op without
        /// any fix or permission.
        private func centerOnUserLocation() {
            guard let mapView,
                  let coordinate = LocationService.shared.getGPSCoordinates(),
                  CLLocationCoordinate2DIsValid(coordinate) else { return }
            mapView.setCenter(coordinate, zoomLevel: max(mapView.zoomLevel, 9), animated: true)
        }

        func tearDown() {
            isTornDown = true
            radarLayer?.stopPlayback()
            radarLayer?.purgeTextures()
            modelLayer?.stopPlayback()
            modelLayer?.purgeTextures()
            cloudsLayer?.purgeTextures()
            userDotPulseTimer?.invalidate()
            userDotPulseTimer = nil
        }

        /// Logs a sync-blocking reason once per transition (not per call) — makes a
        /// permanently-stuck guard visible in the log without spamming.
        func blocked(_ reason: String?) {
            guard lastBlockReason != reason else { return }
            lastBlockReason = reason
            if let reason {
                weatherMapLogger.info("sync blocked: \(reason, privacy: .public)")
            }
        }

        /// Re-runs `syncAll` whenever an observable property it reads changes
        /// (radar state, tile-layer state, settings). SwiftUI's diffing cannot
        /// deliver this: the representable's stored properties are bitwise-identical
        /// across those mutations, so `updateUIView` is skipped no matter what the
        /// parent body observes.
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
            // A (re)loaded style contains none of our layers/sources/images —
            // drop every cached handle so syncAll rebuilds them in THIS style.
            // First load: everything is nil already, all no-ops.
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
                // The viewport is an input to the alert-polygon fetch box but
                // not an observable one — re-run the sync once the camera
                // settles so a long pan or zoom-out refetches the warnings
                // for the newly visible area.
                self.syncAll()
            }
            interactionEndWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
        }

        // MARK: Sync (single entry point; reads register observation dependencies)

        func syncAll() {
            guard !isTornDown else { return }
            // Read EVERY observable input up front, before the guards: syncAll is
            // re-armed via withObservationTracking, and an early return that skipped
            // these reads would register no dependencies — the observation loop (and
            // with it the whole map) would die on the first blocked call.
            let settings = parent.settingsService
            let radarActive = settings.oscarRadarLayer
            let smoothMotion = settings.radarSmoothMotion
            let softRendering = settings.radarSoftRendering
            let motionArrows = settings.radarMotionArrows
            let valueBubbles = settings.mapValueBubbles
            let activeTileLayer = settings.activeTileLayer
            let alertPolygons = settings.showAlertPolygons
            let stormCells = settings.showStormCells
            let isobars = settings.showIsobars || activeTileLayer?.isPressureLayer == true
            let radarRegion = settings.oscarRadarRegion
            // Registers the observation dependency; the value itself reaches the
            // layers via `parent.overlayOpacity` on the next updateUIView pass.
            _ = settings.mapOverlayOpacity
            let basemapStyle = settings.mapBasemapStyle

            let radarState = parent.oscarRadarState
            let radarBounds = radarState?.bounds
            let radarFrame = radarState?.currentFrame
            let radarNext = radarState?.nextFrame
            let radarRenderedIndex = radarState?.renderFrameIndex ?? radarState?.currentFrameIndex ?? 0
            let radarLoadedCount = radarState?.loadedFrameIndices.count ?? 0
            let radarFrameCount = radarState?.frames.count ?? 0
            let radarIsPlaying = radarState?.isPlaying ?? false
            let radarMotion = radarState?.motion

            let cloudsActive = settings.cloudLayerActive
            let cloudState = parent.cloudLayerState
            let cloudBounds = cloudState?.bounds
            let cloudMotion = cloudState?.motion
            let cloudIsPlaying = cloudState?.isPlaying ?? false
            // Registers the dependency that re-fires the sync when cloud
            // metadata/payloads land (payloads themselves are ObservationIgnored).
            _ = cloudState?.loadRevision
            _ = cloudState?.isActive
            _ = cloudState?.currentFrameIndex
            _ = cloudState?.renderFrameIndex

            let modelState = parent.modelGridState
            let modelBounds = modelState?.bounds
            let modelFrame = modelState?.currentFrame
            let modelFrameKey = modelState?.currentFrameKey
            let modelNext = modelState?.nextFrameKeyed
            let modelIsPlaying = modelState?.isPlaying ?? false
            let modelMotion = modelState?.motion
            // Observation re-arm reads (not passed anywhere): currentLayer and the
            // frame indices must be read HERE so withObservationTracking re-fires
            // syncAll when they change — currentFrame/currentFrameKey read them
            // behind guards that can hide them from the tracker on some paths.
            _ = modelState?.currentLayer
            _ = modelState?.renderFrameIndex
            _ = modelState?.currentFrameIndex

            // Style switch: setting styleURL reloads the style; didFinishLoading
            // drops every cached layer handle and this sync path rebuilds them.
            if let mapView, mapView.styleURL != basemapStyle.styleURL {
                mapView.styleURL = basemapStyle.styleURL
                return blocked("style reloading")
            }

            guard let style = mapView?.style else { return blocked("style not loaded") }
            blocked(nil)

            syncClouds(style: style, active: cloudsActive, state: cloudState,
                       bounds: cloudBounds, motion: cloudMotion,
                       cloudIsPlaying: cloudIsPlaying, smoothMotion: smoothMotion)
            syncRadar(style: style, active: radarActive, state: radarState,
                      bounds: radarBounds,
                      frame: radarFrame, next: radarNext, renderedIndex: radarRenderedIndex,
                      loadedCount: radarLoadedCount, frameCount: radarFrameCount,
                      isPlaying: radarIsPlaying, motion: radarMotion, smoothMotion: smoothMotion,
                      softRendering: softRendering, arrowsEnabled: motionArrows)
            syncModelLayer(style: style, selection: activeTileLayer, state: modelState,
                           bounds: modelBounds, payload: modelFrame, frameKey: modelFrameKey,
                           next: modelNext, isPlaying: modelIsPlaying, motion: modelMotion,
                           smoothMotion: smoothMotion, softRendering: softRendering)
            syncValueBubbles(style: style, selection: activeTileLayer, enabled: valueBubbles,
                             payload: modelFrame, frameKey: modelFrameKey)
            // Isobars ride the hourly model frame keys, so they need a model layer —
            // the 5-minute radar timeline has no matching pressure fields.
            syncIsobars(style: style, active: isobars && activeTileLayer != nil,
                        selection: activeTileLayer, frameKey: modelFrameKey)
            syncAlertPolygons(style: style, active: alertPolygons)
            // Cell tracks are radar-scale nowcasts — they'd be misleading floating
            // over a model forecast layer, so they require the radar to be active.
            syncStormCells(style: style, active: stormCells && radarActive, region: radarRegion)
            syncWindParticles(selection: activeTileLayer, state: modelState)
            syncUserLocationDot(style: style)
            // Last: chips and the selected-city marker re-assert themselves as
            // the topmost layers, so they must run after every sync that may
            // have added layers above them. The marker runs after the chips —
            // the selected city always reads above its neighbors.
            syncCityChips(style: style)
            syncSelectedCityMarker(style: style)
        }

        /// One pending delayed `syncAll` — used when a layer can't build textures
        /// yet because MapLibre hasn't delivered the Metal device (`didMove`).
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

        /// Overlay layers (radar, model image) sit above ALL geometry
        /// (roads included — "below the first symbol layer" landed under the streets:
        /// the dark style's first symbol is a water label that sits below the road
        /// lines), below the trailing labels.
        func insertOverlayLayer(_ layer: MLNStyleLayer, in style: MLNStyle) {
            if let lastGeometry = style.layers.last(where: { !($0 is MLNSymbolStyleLayer) }) {
                style.insertLayer(layer, above: lastGeometry)
            } else {
                style.addLayer(layer)
            }
        }

        /// After a radar-region switch the map can be looking at the wrong continent
        /// (Berlin → USA radar). If the camera centre is outside the new region's
        /// footprint, fly to the region instead of showing empty map.
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
            // Rough fit: world is 360° at zoom 0; pad by one notch for UI chrome.
            let zoom = max(2.5, log2(360.0 / lonSpan) + 0.5)
            mapView.setCenter(regionCenter, zoomLevel: zoom, animated: animated)
        }
    }
}
