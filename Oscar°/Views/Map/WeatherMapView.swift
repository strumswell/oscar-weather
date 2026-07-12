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
//  Other layers: radar motion arrows (server raster tiles), ICON-D2/GFS model
//  images (MLNImageSource), wind particles (sibling Metal-free
//  overlay view), selected-city marker, user location.
//
//  Basemap: OpenFreeMap (no API key). The MapLibre attribution button stays
//  visible — it carries the OpenFreeMap/OSM (ODbL) attribution.
//

import CoreLocation
import MapLibre
import Metal
import OSLog
import Observation
import SwiftUI
import UIKit

private let mapLibreLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "WeatherMap")

// MARK: - Map view (representable)

struct WeatherMapView: UIViewRepresentable {
    let settingsService: SettingService
    var coordinates: CLLocationCoordinate2D
    var cities: [City]
    var overlayOpacity: Double
    var userActionAllowed: Bool
    var showWindParticles: Bool
    var oscarRadarState: OscarRadarState?
    var modelGridState: ModelGridLayerState?
    /// Tap on warning polygon(s) → all warnings under the finger, most severe first.
    var onAlertsTapped: (([WeatherAlertInfo]) -> Void)? = nil
    /// Tap on a storm-cell marker/footprint → that cell's details.
    var onCellTapped: ((StormCellInfo) -> Void)? = nil

    fileprivate static let radarLayerID = "oscar-radar-layer"
    fileprivate static let modelLayerID = "oscar-model-image"
    fileprivate static let alertSourceID = "oscar-alert-polygons"
    fileprivate static let alertFillLayerID = "oscar-alert-fill"
    fileprivate static let alertOutlineLayerID = "oscar-alert-outline"
    fileprivate static let isobarSourceID = "oscar-isobar-source"
    fileprivate static let isobarCasingLayerID = "oscar-isobar-casing"
    fileprivate static let isobarLineLayerID = "oscar-isobar-line"
    fileprivate static let isobarLabelLayerID = "oscar-isobar-label"
    fileprivate static let isobarCenterLayerID = "oscar-isobar-center"
    fileprivate static let isobarCenterValueLayerID = "oscar-isobar-center-value"
    fileprivate static let cellPointSourceID = "oscar-cells-points"
    fileprivate static let cellTrackSourceID = "oscar-cells-tracks"
    fileprivate static let cellConeSourceID = "oscar-cells-cones"
    fileprivate static let cellFootprintSourceID = "oscar-cells-footprints"
    fileprivate static let cellTickSourceID = "oscar-cells-ticks"
    fileprivate static let cellHeadSourceID = "oscar-cells-heads"
    fileprivate static let cellCircleLayerID = "oscar-cells-circle"
    fileprivate static let cellTrackLayerID = "oscar-cells-track"
    fileprivate static let cellConeLayerID = "oscar-cells-cone"
    fileprivate static let cellFootprintFillLayerID = "oscar-cells-footprint-fill"
    fileprivate static let cellFootprintLineLayerID = "oscar-cells-footprint-line"
    fileprivate static let cellTickLayerID = "oscar-cells-tick"
    fileprivate static let cellTickLabelLayerID = "oscar-cells-tick-label"
    fileprivate static let cellHeadLayerID = "oscar-cells-head"
    fileprivate static let cellArrowImageName = "oscar-cell-arrow"

    /// Initial camera zoom, overridable via `-mapInitialZoom <z>` (UserDefaults
    /// argument domain or persisted default) — a dev/staging knob like
    /// `-radarBaseURL`, unset in every normal launch.
    private static var initialZoom: Double {
        let override = UserDefaults.standard.double(forKey: "mapInitialZoom")
        return override > 0 ? override : 7
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        // OpenFreeMap basemap (no API key), user-selectable style — Fiord default.
        let mapView = MLNMapView(frame: .zero, styleURL: settingsService.mapBasemapStyle.styleURL)
        mapLibreLogger.info("map view created role=\(userActionAllowed ? "fullscreen" : "preview", privacy: .public)")
        mapView.delegate = context.coordinator
        mapView.setCenter(coordinates, zoomLevel: Self.initialZoom, animated: false)
        mapView.allowsTilting = false
        // MapLibre requests location permission itself the moment this is enabled
        // while the status is undetermined — and the preview lives inside NowView,
        // which renders at launch (even behind onboarding). So show the user dot
        // only once access already exists; updateUIView turns it on after a grant.
        mapView.showsUserLocation = Self.locationAuthorized
        // OpenFreeMap/OSM (ODbL) attribution is an always-visible corner label
        // (MapAttributionLabel, drawn by the SwiftUI host) — the OSMF-preferred
        // form — so MapLibre's ⓘ button and wordmark both stay hidden.
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true
        // North stays resettable via the two-finger gesture; the transient
        // compass overlay just fights the close/layer buttons in that corner.
        mapView.compassView.isHidden = true
        if !userActionAllowed {
            mapView.allowsScrolling = false
            mapView.allowsZooming = false
            mapView.allowsRotating = false
        }

        // Feature tap-through (fullscreen only): warnings + storm cells. The map's
        // own tap recognizers must fail first (annotation selection, double-tap
        // zoom) — the standard MapLibre feature-query pattern.
        if userActionAllowed {
            let tap = UITapGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
            for recognizer in mapView.gestureRecognizers ?? []
            where recognizer is UITapGestureRecognizer {
                tap.require(toFail: recognizer)
            }
            mapView.addGestureRecognizer(tap)
        }

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
    /// prompt. Gates the map's user-location dot so the launch-time NowView preview
    /// can't raise the system permission dialog before the onboarding step does.
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

        // Static (non-interactive) previews follow the selected location.
        if !userActionAllowed {
            let current = mapView.centerCoordinate
            let distance = CLLocation(latitude: current.latitude, longitude: current.longitude)
                .distance(from: CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude))
            if distance > 1000 {
                mapView.setCenter(coordinates, zoomLevel: Self.initialZoom, animated: false)
                context.coordinator.recenterIntoRadarBoundsIfNeeded(animated: false)
            }
        }
    }

    static func dismantleUIView(_ mapView: MLNMapView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: WeatherMapView
        weak var mapView: MLNMapView?
        weak var windParticleView: WindParticleView?

        private var radarLayer: RadarCustomStyleLayer?
        private var lastFrameKey: String?
        private var lastRenderIndex = -1
        private var lastBounds: OscarRadarBounds?
        private var radarPaletteId: String?
        private var isFetchingPalette = false
        private var lastBlockReason: String?

        private var arrowSourceID: String?

        private var modelLayer: RadarCustomStyleLayer?
        private var modelPaletteId: String?
        private var modelPalette: [PixelRGBA]?
        private var lastModelFrameKey: String?
        private var lastModelBounds: OscarRadarBounds?

        private var bubbleSyncKey: String?
        private var lastBubbleSignature: String?
        private var registeredBubbleIcons: Set<String> = []

        private var alertOverlayData: Data?
        private var alertOverlayFetchedAt: Date?
        private var alertOverlayCenter: CLLocationCoordinate2D?
        private var isLoadingAlertOverlay = false

        private var stormCells: [StormCellInfo]?
        private var stormCellsFetchedAt: Date?
        private var stormCellsRegion: RadarRegion?
        private var isLoadingStormCells = false

        // Per-frame isobar GeoJSON, keyed "framesEndpoint/frameKey" (see syncIsobars).
        private var isobarShapes: [String: MLNShape] = [:]
        private var isobarFetchesInFlight: Set<String> = []
        private var isobarFailures: [String: Date] = [:]
        private var isobarSyncKey: String?


        private var selectedCityAnnotation: MLNPointAnnotation?
        private var selectedCityIdentity: String?

        private var lastWindFrameKey: String?

        private var isObservationLoopAlive = false
        private var isTornDown = false
        nonisolated(unsafe) private var reduceMotionObserver: NSObjectProtocol?
        nonisolated(unsafe) private var interactionEndWorkItem: DispatchWorkItem?
        nonisolated(unsafe) private var userDotPulseTimer: Timer?
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
        }

        deinit {
            interactionEndWorkItem?.cancel()
            userDotPulseTimer?.invalidate()
            if let reduceMotionObserver {
                NotificationCenter.default.removeObserver(reduceMotionObserver)
            }
        }

        func tearDown() {
            isTornDown = true
            radarLayer?.stopPlayback()
            modelLayer?.stopPlayback()
            userDotPulseTimer?.invalidate()
            userDotPulseTimer = nil
        }

        /// Logs a sync-blocking reason once per transition (not per call) — makes a
        /// permanently-stuck guard visible in the log without spamming.
        private func blocked(_ reason: String?) {
            guard lastBlockReason != reason else { return }
            lastBlockReason = reason
            if let reason {
                let role = parent.userActionAllowed ? "fullscreen" : "preview"
                mapLibreLogger.info("sync blocked [\(role, privacy: .public)]: \(reason, privacy: .public)")
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

        nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            MainActor.assumeIsolated {
                mapLibreLogger.info("style loaded role=\(self.parent.userActionAllowed ? "fullscreen" : "preview", privacy: .public)")
                // A (re)loaded style contains none of our layers/sources/images —
                // drop every cached handle so syncAll rebuilds them in THIS style.
                // First load: everything is nil already, all no-ops.
                radarLayer?.stopPlayback()
                radarLayer = nil
                lastFrameKey = nil
                lastRenderIndex = -1
                lastBounds = nil
                radarPaletteId = nil
                modelLayer?.stopPlayback()
                modelLayer = nil
                modelPaletteId = nil
                modelPalette = nil
                lastModelFrameKey = nil
                lastModelBounds = nil
                arrowSourceID = nil
                bubbleSyncKey = nil
                lastBubbleSignature = nil
                registeredBubbleIcons.removeAll()
                isobarSyncKey = nil
                syncAll()
            }
        }

        // MARK: Interaction plumbing (pauses prefetch during gestures, like MapKit did)

        nonisolated func mapView(_ mapView: MLNMapView, regionWillChangeAnimated animated: Bool) {
            MainActor.assumeIsolated {
                guard parent.userActionAllowed else { return }
                interactionEndWorkItem?.cancel()
                interactionEndWorkItem = nil
                guard !isMapInteractionActive else { return }
                isMapInteractionActive = true
                parent.oscarRadarState?.beginMapInteraction()
                parent.modelGridState?.beginMapInteraction()
            }
        }

        nonisolated func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            MainActor.assumeIsolated {
                windParticleView?.onMapRegionChanged()
                guard parent.userActionAllowed, isMapInteractionActive else { return }
                interactionEndWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.isMapInteractionActive = false
                    self.parent.oscarRadarState?.endMapInteraction()
                    self.parent.modelGridState?.endMapInteraction()
                }
                interactionEndWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
            }
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
            let radarProduct = radarState?.product ?? .precipitation
            let radarBounds = radarState?.bounds
            let radarFrame = radarState?.currentFrame
            let radarNext = radarState?.nextFrame
            let radarRenderedIndex = radarState?.renderFrameIndex ?? radarState?.currentFrameIndex ?? 0
            let radarLoadedCount = radarState?.loadedFrameIndices.count ?? 0
            let radarFrameCount = radarState?.frames.count ?? 0
            let radarIsPlaying = radarState?.isPlaying ?? false
            let radarMotion = radarState?.motion

            let gfsState = parent.modelGridState
            let gfsBounds = gfsState?.bounds
            let gfsFrame = gfsState?.currentFrame
            let gfsFrameKey = gfsState?.currentFrameKey
            let gfsNext = gfsState?.nextFrameKeyed
            let gfsIsPlaying = gfsState?.isPlaying ?? false
            let gfsMotion = gfsState?.motion
            // Observation re-arm reads (not passed anywhere): currentLayer and the
            // frame indices must be read HERE so withObservationTracking re-fires
            // syncAll when they change — currentFrame/currentFrameKey read them
            // behind guards that can hide them from the tracker on some paths.
            _ = gfsState?.currentLayer
            _ = gfsState?.renderFrameIndex
            _ = gfsState?.currentFrameIndex

            // Style switch: setting styleURL reloads the style; didFinishLoading
            // drops every cached layer handle and this sync path rebuilds them.
            if let mapView, mapView.styleURL != basemapStyle.styleURL {
                mapView.styleURL = basemapStyle.styleURL
                return blocked("style reloading")
            }

            guard let style = mapView?.style else { return blocked("style not loaded") }
            blocked(nil)

            syncRadar(style: style, active: radarActive, state: radarState, product: radarProduct,
                      bounds: radarBounds,
                      frame: radarFrame, next: radarNext, renderedIndex: radarRenderedIndex,
                      loadedCount: radarLoadedCount, frameCount: radarFrameCount,
                      isPlaying: radarIsPlaying, motion: radarMotion, smoothMotion: smoothMotion,
                      softRendering: softRendering, arrowsEnabled: motionArrows)
            syncModelLayer(style: style, selection: activeTileLayer, state: gfsState,
                           bounds: gfsBounds, payload: gfsFrame, frameKey: gfsFrameKey,
                           next: gfsNext, isPlaying: gfsIsPlaying, motion: gfsMotion,
                           smoothMotion: smoothMotion, softRendering: softRendering)
            syncValueBubbles(style: style, selection: activeTileLayer, enabled: valueBubbles,
                             payload: gfsFrame, frameKey: gfsFrameKey)
            // Isobars ride the hourly model frame keys, so they need a model layer —
            // the 5-minute radar timeline has no matching pressure fields.
            syncIsobars(style: style, active: isobars && activeTileLayer != nil,
                        selection: activeTileLayer, frameKey: gfsFrameKey)
            syncAlertPolygons(style: style, active: alertPolygons)
            // Cell tracks are radar-scale nowcasts — they'd be misleading floating
            // over a model forecast layer, so they require the radar to be active.
            syncStormCells(style: style, active: stormCells && radarActive, region: radarRegion)
            syncWindParticles(selection: activeTileLayer, state: gfsState)
            syncSelectedCityAnnotation()
            syncUserLocationDot(style: style)
        }

        // MARK: Radar (custom layer + motion morph + arrows)

        private func syncRadar(
            style: MLNStyle, active: Bool, state: OscarRadarState?, product: RadarProduct,
            bounds: OscarRadarBounds?, frame: OscarRadarFrame?, next: OscarRadarFrame?,
            renderedIndex: Int, loadedCount: Int, frameCount: Int,
            isPlaying: Bool, motion: RadarMotionData?, smoothMotion: Bool,
            softRendering: Bool, arrowsEnabled: Bool
        ) {
            guard active, let state else {
                removeArrowLayer(from: style)
                if let layer = radarLayer {
                    layer.stopPlayback()
                    layer.purgeTextures()
                    style.removeLayer(layer)
                    radarLayer = nil
                    lastFrameKey = nil
                    lastRenderIndex = -1
                    lastBounds = nil
                    radarPaletteId = nil
                }
                return
            }
            guard let bounds else { return blocked("no radar bounds (metadata not loaded)") }

            let layer: RadarCustomStyleLayer
            if let existing = radarLayer {
                layer = existing
            } else {
                layer = RadarCustomStyleLayer(identifier: WeatherMapView.radarLayerID)
                insertOverlayLayer(layer, in: style)
                radarLayer = layer
            }

            layer.configure(bounds: bounds, opacity: Float(parent.overlayOpacity))
            // Typed grids are block-coded (type × intensity) — the categorical modes
            // pick the block from the nearest sample; the soft variant smooths the
            // intensity inside it (Weichzeichnen without fabricated types).
            layer.setSampling(product == .precipitationTyped
                              ? (softRendering ? .categoricalSoft : .categorical)
                              : softRendering ? .soft : .hard)
            layer.setMotion(motion)

            // Product switch on the same layer: palette AND textures must go —
            // grid indices mean different things per palette and frame keys are
            // bare timestamps that collide across products.
            if radarPaletteId != product.colormapId {
                radarPaletteId = product.colormapId
                layer.clearPalette()
                layer.purgeTextures()
                lastFrameKey = nil
                lastRenderIndex = -1
            }
            if !layer.hasPalette, !isFetchingPalette {
                isFetchingPalette = true
                let paletteId = product.colormapId
                Task { @MainActor [weak self, weak layer] in
                    let palette = await OscarRadarState.resolvedPalette(id: paletteId)
                    if self?.radarPaletteId == paletteId {
                        layer?.setPalette(palette)
                        layer?.setNeedsDisplay()
                    }
                    self?.isFetchingPalette = false
                }
            }

            if lastBounds != bounds {
                // Region switch: frame keys are bare timestamps that collide across
                // regions — the texture cache must go too.
                layer.purgeTextures()
                lastBounds = bounds
                lastFrameKey = nil
                lastRenderIndex = -1
                recenterIntoRadarBoundsIfNeeded(animated: parent.userActionAllowed)
            }

            // Typed playback morphs too — categorical mode blends in color space,
            // so no index sweeps through unrelated types.
            let interpolate = smoothMotion && !UIAccessibility.isReduceMotionEnabled

            defer {
                // Playback ownership mirrors the old Metal overlay: the layer's display
                // link owns phase + frame advancement; the state's 0.5 s Timer would
                // double-advance, so it is cancelled while the layer runs.
                if isPlaying, frame != nil {
                    state.cancelInternalTimer()
                    layer.startPlayback(interpolate: interpolate) { [weak state] in
                        state?.advanceFrame()
                    }
                } else if layer.isPlaybackActive {
                    layer.stopPlayback()
                }
                syncArrowLayer(style: style, state: state, frame: frame, isPlaying: isPlaying,
                               enabled: arrowsEnabled)
            }

            guard let frame else {
                return blocked("no current radar frame (loaded=\(loadedCount)/\(frameCount))")
            }
            guard lastFrameKey != frame.key || lastRenderIndex != renderedIndex else { return }
            blocked(nil)

            guard let textureA = layer.texture(for: frame) else {
                // No Metal device yet (didMove pending) — retry without stamping
                // lastFrameKey, or this frame would never be re-displayed.
                scheduleSyncRetry()
                return
            }
            let textureB = next.flatMap { layer.texture(for: $0) }
            // Flow lookup: exact adjacent pair first; when the displayed pair skips
            // served frames (progressive loading), fall back to the FROM frame's
            // field and rescale by the real timestamp gap. Never morph backwards
            // across the loop seam (negative gap) or across data holes (> 1 h).
            var flowFieldIndex: Int?
            var flowScale: Float = 0
            if let motion, let next {
                let pair = motion.pairs["\(frame.key)|\(next.key)"] ?? motion.pairsByFrom[frame.key]
                if let pair,
                   let gap = OscarRadarState.minutesBetween(frame.timestamp, next.timestamp),
                   gap > 0, gap <= 60 {
                    flowFieldIndex = pair.fieldIndex
                    flowScale = Float(gap) / Float(motion.stepMinutes)
                }
            }
            layer.display(frameA: textureA, frameB: textureB,
                          flowFieldIndex: flowFieldIndex, flowScale: flowScale)
            lastFrameKey = frame.key
            lastRenderIndex = renderedIndex
        }

        /// Motion arrows for the CURRENT observed frame, built client-side from the
        /// /motion flow field + the frame's in-RAM value grid (one point feature per
        /// coarse cell that carries precipitation). Replaces the server raster
        /// vector tiles, whose stretched old-zoom tiles flashed huge arrows during
        /// zoom transitions — symbol icons are screen-space (no scaling flicker)
        /// and MapLibre's collision thins them automatically when zooming out.
        /// Hidden during playback, like the raster tiles were.
        private static let arrowSourceIdentifier = "oscar-motion-arrows"
        private static let arrowImageName = "oscar-motion-arrow"

        private func syncArrowLayer(style: MLNStyle, state: OscarRadarState,
                                    frame: OscarRadarFrame?, isPlaying: Bool, enabled: Bool) {
            let desiredID: String?
            if let frame, !isPlaying, enabled, let motion = state.motion,
               let pair = motion.pairsByFrom[frame.key] {
                desiredID = "\(state.region.pathComponent)-\(frame.key)-\(pair.fieldIndex)"
            } else {
                desiredID = nil
            }
            guard desiredID != arrowSourceID else { return }
            guard let desiredID, let frame, let motion = state.motion,
                  let pair = motion.pairsByFrom[frame.key], let bounds = state.bounds else {
                removeArrowLayer(from: style)
                return
            }

            let features = RadarMotionArrows.arrowFeatures(
                motion: motion, fieldIndex: pair.fieldIndex,
                grid: frame.gridPayload, bounds: bounds)
            let shape = MLNShapeCollectionFeature(shapes: features)

            if let source = style.source(withIdentifier: Self.arrowSourceIdentifier) as? MLNShapeSource {
                source.shape = shape
            } else {
                style.setImage(RadarArrowGeometry.arrowImage(), forName: Self.arrowImageName)
                let source = MLNShapeSource(identifier: Self.arrowSourceIdentifier, shape: shape)
                let layer = MLNSymbolStyleLayer(identifier: Self.arrowSourceIdentifier, source: source)
                layer.iconImageName = NSExpression(forConstantValue: Self.arrowImageName)
                layer.iconRotation = NSExpression(forKeyPath: "rotation")
                layer.iconScale = NSExpression(forKeyPath: "scale")
                // Map-aligned: arrows keep their geographic direction when the map
                // rotates; their SIZE stays screen-space at every zoom.
                layer.iconRotationAlignment = NSExpression(forConstantValue: "map")
                layer.iconAllowsOverlap = NSExpression(forConstantValue: false)
                layer.iconOpacity = NSExpression(forConstantValue: 0.9)
                style.addSource(source)
                style.addLayer(layer)     // topmost — arrows read above the labels
            }
            arrowSourceID = desiredID
        }

        private func removeArrowLayer(from style: MLNStyle) {
            guard arrowSourceID != nil else { return }
            if let layer = style.layer(withIdentifier: Self.arrowSourceIdentifier) { style.removeLayer(layer) }
            if let source = style.source(withIdentifier: Self.arrowSourceIdentifier) { style.removeSource(source) }
            arrowSourceID = nil
        }

        // MARK: ICON-D2 / GFS model layer (value grids + palette, like the radar)

        private func syncModelLayer(
            style: MLNStyle, selection: WeatherTileLayer?, state: ModelGridLayerState?,
            bounds: OscarRadarBounds?, payload: RadarGridPayload?, frameKey: String?,
            next: (key: String, payload: RadarGridPayload)?, isPlaying: Bool,
            motion: RadarMotionData?, smoothMotion: Bool, softRendering: Bool
        ) {
            guard let selection, let state else {
                removeModelLayer(from: style)
                return
            }
            guard let bounds else { return }

            let layer: RadarCustomStyleLayer
            if let existing = modelLayer {
                layer = existing
            } else {
                layer = RadarCustomStyleLayer(identifier: WeatherMapView.modelLayerID)
                insertOverlayLayer(layer, in: style)
                modelLayer = layer
            }
            layer.configure(bounds: bounds, opacity: Float(parent.overlayOpacity))
            layer.setSampling(softRendering ? .soft : .hard)
            layer.setMotion(motion)

            // Variable switch: grid indices mean different things per palette and
            // frame keys collide across variables — palette and textures must go.
            if modelPaletteId != selection.colormapId {
                modelPaletteId = selection.colormapId
                modelPalette = nil
                layer.clearPalette()
                layer.purgeTextures()
                lastModelFrameKey = nil
                let colormapId = selection.colormapId
                Task { @MainActor [weak self] in
                    guard let palette = await ModelGridLayerState.palette(for: colormapId) else {
                        guard let self, self.modelPaletteId == colormapId else { return }
                        self.modelPaletteId = nil
                        return
                    }
                    guard let self, self.modelPaletteId == colormapId else { return }
                    self.modelPalette = palette
                    self.syncAll()
                }
                return
            }
            // Re-applied until it sticks: `setPalette` needs the Metal device from the
            // layer's `didMove`, which MapLibre can deliver AFTER a fast (local/cached)
            // palette fetch — a one-shot set would be lost forever.
            if !layer.hasPalette, let modelPalette {
                layer.setPalette(modelPalette)
                layer.setNeedsDisplay()
            }

            if lastModelBounds != bounds {
                layer.purgeTextures()
                lastModelBounds = bounds
                lastModelFrameKey = nil
            }

            defer {
                // Same playback ownership rule as the radar layer: while playing,
                // the layer's display link owns phase + advancement (hourly frames
                // morph along the model flow — precip — or cross-fade in data
                // space); the state's 0.8 s Timer would double-advance, so it is
                // cancelled while the layer runs.
                // Fullscreen only: the NowView preview SHARES this state — a second
                // display link would double-advance every tick.
                if isPlaying, payload != nil, parent.userActionAllowed {
                    state.cancelInternalTimer()
                    layer.startPlayback(
                        interval: 0.8,
                        interpolate: smoothMotion && !UIAccessibility.isReduceMotionEnabled
                    ) { [weak state] in
                        state?.advanceFrame()
                    }
                } else if layer.isPlaybackActive {
                    layer.stopPlayback()
                }
            }

            guard let payload, let frameKey else { return }
            // Re-display when either end of the pair changes (the next frame can
            // arrive later than the current one during progressive loading).
            let pairKey = "\(frameKey)|\(next?.key ?? "-")"
            guard lastModelFrameKey != pairKey else { return }
            guard let textureA = layer.texture(key: frameKey, payload: payload) else {
                // No Metal device yet (didMove pending). Do NOT stamp pairKey — a
                // cached palette + grid can resolve before didMove, and nothing
                // observable changes when the device lands, so nudge a retry.
                scheduleSyncRetry()
                return
            }
            let textureB = next.flatMap { layer.texture(key: $0.key, payload: $0.payload) }
            // Flow lookup, precipitation only — temperature/wind blend in data
            // space without warping. Exact adjacent pair first; FROM-frame fallback
            // (rescaled by the real timestamp gap) when the displayed pair skips
            // served frames. Hourly pairs arrive with gap_minutes=60, right at the
            // radar path's ceiling: the shader scales the per-5-min field by
            // 60/5 = 12 — the full hour of motion, dry pairs share a zero field
            // (degrades to the plain cross-fade). Larger gaps (skipped frames
            // while loading) never morph.
            var flowFieldIndex: Int?
            var flowScale: Float = 0
            if selection.morphsAlongMotion, let motion, let next {
                let pair = motion.pairs["\(frameKey)|\(next.key)"] ?? motion.pairsByFrom[frameKey]
                if let pair,
                   let from = state.timestamp(forKey: frameKey),
                   let to = state.timestamp(forKey: next.key),
                   let gap = OscarRadarState.minutesBetween(from, to),
                   gap > 0, gap <= 60 {
                    flowFieldIndex = pair.fieldIndex
                    flowScale = Float(gap) / Float(motion.stepMinutes)
                }
            }
            layer.display(frameA: textureA, frameB: textureB,
                          flowFieldIndex: flowFieldIndex, flowScale: flowScale)
            lastModelFrameKey = pairKey
        }

        /// One pending delayed `syncAll` — used when a layer can't build textures
        /// yet because MapLibre hasn't delivered the Metal device (`didMove`).
        private var syncRetryScheduled = false
        private func scheduleSyncRetry() {
            guard !syncRetryScheduled else { return }
            syncRetryScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                self.syncRetryScheduled = false
                self.syncAll()
            }
        }

        private func removeModelLayer(from style: MLNStyle) {
            guard let layer = modelLayer else { return }
            layer.stopPlayback()
            layer.purgeTextures()
            style.removeLayer(layer)
            modelLayer = nil
            modelPaletteId = nil
            modelPalette = nil
            lastModelFrameKey = nil
            lastModelBounds = nil
        }

        // MARK: Severe-weather warning polygons

        /// Warning areas draw ON TOP of whichever radar/model layer is active —
        /// translucent severity-colored fills plus a crisp outline, refreshed at
        /// most every 5 minutes while the toggle is on.
        private func syncAlertPolygons(style: MLNStyle, active: Bool) {
            let sourceID = WeatherMapView.alertSourceID
            let fillID = WeatherMapView.alertFillLayerID
            let lineID = WeatherMapView.alertOutlineLayerID
            guard active else {
                removeAlertPolygonLayers(from: style)
                return
            }

            let center = mapView?.centerCoordinate ?? parent.coordinates
            let isStale = alertOverlayFetchedAt.map { Date().timeIntervalSince($0) > 300 } ?? true
            // The fetch box is viewport-sized (±5°/±7° around the fetch center), so a
            // long pan must refetch even inside the 5-min window — beyond ~2° the map
            // edge approaches the old box's edge and warnings would silently stop.
            let drifted = alertOverlayCenter.map {
                abs($0.latitude - center.latitude) > 2 || abs($0.longitude - center.longitude) > 3
            } ?? false
            if (isStale || drifted), !isLoadingAlertOverlay {
                isLoadingAlertOverlay = true
                Task { @MainActor [weak self] in
                    defer { self?.isLoadingAlertOverlay = false }
                    do {
                        let data = try await APIClient.shared.getWeatherAlertPolygons(around: center)
                        guard let self, !self.isTornDown else { return }
                        self.alertOverlayData = data
                        self.alertOverlayFetchedAt = Date()
                        self.alertOverlayCenter = center
                        // Swap the shape into the existing source instead of tearing the
                        // source + layers down: MapLibre re-tiles a fresh GeoJSON source
                        // asynchronously, so a rebuild blanks the polygons for a beat on
                        // every refresh (the isobar sources use the same pattern).
                        if let style = self.mapView?.style,
                           let source = style.source(withIdentifier: WeatherMapView.alertSourceID) as? MLNShapeSource,
                           let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) {
                            source.shape = shape
                        } else {
                            self.syncAll()
                        }
                    } catch {
                        mapLibreLogger.error("Alert polygon fetch failed: \(error.localizedDescription, privacy: .public)")
                        // Back off until the staleness window elapses; keep stale data
                        // visible and stop drift-retriggering for the attempted spot.
                        self?.alertOverlayFetchedAt = Date()
                        self?.alertOverlayCenter = center
                    }
                }
            }

            guard style.source(withIdentifier: sourceID) == nil else { return }
            guard let data = alertOverlayData,
                  let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue)
            else { return }

            let source = MLNShapeSource(identifier: sourceID, shape: shape, options: nil)
            style.addSource(source)

            // DWD severity ranks: 1 Minor (default), 2 Moderate, 3 Severe, 4 Extreme.
            // Typed constructor — MapLibre's NSExpression parser rejects the old
            // MGL_MATCH format-string spelling at runtime.
            let severityColor = NSExpression(
                forMLNMatchingKey: NSExpression(forKeyPath: "severity_rank"),
                in: [
                    NSExpression(forConstantValue: 2): NSExpression(forConstantValue: UIColor.systemOrange),
                    NSExpression(forConstantValue: 3): NSExpression(forConstantValue: UIColor.systemRed),
                    NSExpression(forConstantValue: 4): NSExpression(forConstantValue: UIColor.systemPurple),
                ],
                default: NSExpression(forConstantValue: UIColor.systemYellow)
            )
            let fill = MLNFillStyleLayer(identifier: fillID, source: source)
            fill.fillColor = severityColor
            fill.fillOpacity = NSExpression(forConstantValue: 0.16)
            insertOverlayLayer(fill, in: style)

            let outline = MLNLineStyleLayer(identifier: lineID, source: source)
            outline.lineColor = severityColor
            outline.lineWidth = NSExpression(forConstantValue: 1.6)
            outline.lineOpacity = NSExpression(forConstantValue: 0.9)
            insertOverlayLayer(outline, in: style)
        }

        // MARK: Isobars (Großwetterlage overlay)

        /// MSLP isolines + H/T pressure centers (server `/models/{model}/frames/
        /// {key}/pressure/isolines`) over the active model layer — the classic
        /// Großwetterlage look on top of the pressure, temperature, or wind fill.
        /// The per-frame GeoJSON swaps into one shared source while scrubbing (the
        /// value-bubble pattern); fetched shapes are cached per frame key, so a
        /// second playback loop is free.
        private func syncIsobars(style: MLNStyle, active: Bool,
                                 selection: WeatherTileLayer?, frameKey: String?) {
            guard active, let selection, let frameKey else {
                if isobarSyncKey != nil { removeIsobarLayers(from: style) }
                return
            }
            let cacheKey = "\(selection.framesEndpoint)/\(frameKey)"

            if isobarShapes[cacheKey] == nil,
               !isobarFetchesInFlight.contains(cacheKey),
               isobarFailures[cacheKey].map({ Date().timeIntervalSince($0) > 120 }) ?? true {
                isobarFetchesInFlight.insert(cacheKey)
                Task { @MainActor [weak self] in
                    defer { self?.isobarFetchesInFlight.remove(cacheKey) }
                    do {
                        let data = try await APIClient.shared.getPressureIsolines(
                            framesEndpoint: selection.framesEndpoint, frameKey: frameKey)
                        guard let self, !self.isTornDown else { return }
                        guard let shape = try? MLNShape(
                            data: data, encoding: String.Encoding.utf8.rawValue) else {
                            self.isobarFailures[cacheKey] = Date()
                            return
                        }
                        // Frame keys are valid-time stable, so day over day the cache
                        // only grows — reset it before it does.
                        if self.isobarShapes.count > 96 { self.isobarShapes.removeAll() }
                        self.isobarShapes[cacheKey] = shape
                        self.isobarFailures[cacheKey] = nil
                        self.syncAll()
                    } catch {
                        mapLibreLogger.error("Isobar fetch failed: \(error.localizedDescription, privacy: .public)")
                        self?.isobarFailures[cacheKey] = Date()
                    }
                }
            }

            guard let shape = isobarShapes[cacheKey] else {
                clearIsobarSourceIfNeeded(in: style, nextKey: cacheKey)
                return
            }
            ensureIsobarLayers(in: style)
            guard isobarSyncKey != cacheKey else { return }
            (style.source(withIdentifier: WeatherMapView.isobarSourceID) as? MLNShapeSource)?.shape = shape
            isobarSyncKey = cacheKey
        }

        private func clearIsobarSourceIfNeeded(in style: MLNStyle, nextKey: String) {
            guard isobarSyncKey != nil, isobarSyncKey != nextKey else { return }
            (style.source(withIdentifier: WeatherMapView.isobarSourceID) as? MLNShapeSource)?
                .shape = MLNShapeCollectionFeature(shapes: [])
            isobarSyncKey = nil
        }

        /// One shared source; casing + core line pair (readable over both the dark
        /// low end and the near-white 1013 center of the pressure fill), inline
        /// hPa labels, and the H/T center letters with their central pressure.
        private func ensureIsobarLayers(in style: MLNStyle) {
            guard style.source(withIdentifier: WeatherMapView.isobarSourceID) == nil else { return }
            let source = MLNShapeSource(identifier: WeatherMapView.isobarSourceID,
                                        shape: MLNShapeCollectionFeature(shapes: []))
            style.addSource(source)

            // Lines carry `level`, the H/T points carry `kind` — the predicates keep
            // each layer to its half of the shared FeatureCollection.
            let isIsobar = NSPredicate(format: "level != NIL")
            let isCenter = NSPredicate(format: "kind != NIL")
            // Index isobars (multiples of 10/20 hPa) draw bolder.
            func indexWidth(_ index: Double, _ regular: Double) -> NSExpression {
                NSExpression(forConditional: NSPredicate(format: "index == YES"),
                             trueExpression: NSExpression(forConstantValue: index),
                             falseExpression: NSExpression(forConstantValue: regular))
            }

            let casing = MLNLineStyleLayer(identifier: WeatherMapView.isobarCasingLayerID, source: source)
            casing.predicate = isIsobar
            casing.lineColor = NSExpression(forConstantValue: UIColor.black)
            casing.lineOpacity = NSExpression(forConstantValue: 0.28)
            casing.lineWidth = indexWidth(3.2, 2.2)
            casing.lineCap = NSExpression(forConstantValue: "round")
            casing.lineJoin = NSExpression(forConstantValue: "round")
            insertOverlayLayer(casing, in: style)

            let line = MLNLineStyleLayer(identifier: WeatherMapView.isobarLineLayerID, source: source)
            line.predicate = isIsobar
            line.lineColor = NSExpression(forConstantValue: UIColor.white)
            line.lineOpacity = NSExpression(forConstantValue: 0.95)
            line.lineWidth = indexWidth(1.8, 1.0)
            line.lineCap = NSExpression(forConstantValue: "round")
            line.lineJoin = NSExpression(forConstantValue: "round")
            insertOverlayLayer(line, in: style)

            // Inline hPa labels along the lines, above the basemap labels.
            let labels = MLNSymbolStyleLayer(identifier: WeatherMapView.isobarLabelLayerID, source: source)
            labels.predicate = isIsobar
            labels.symbolPlacement = NSExpression(forConstantValue: "line")
            labels.symbolSpacing = NSExpression(forConstantValue: 320)
            labels.maximumTextAngle = NSExpression(forConstantValue: 30)
            labels.text = NSExpression(forKeyPath: "label")
            // The ONLY font stack the OpenFreeMap styles serve glyphs for.
            labels.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
            labels.textFontSize = NSExpression(forConstantValue: 10)
            labels.textColor = NSExpression(forConstantValue: UIColor.white)
            labels.textHaloColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.55))
            labels.textHaloWidth = NSExpression(forConstantValue: 1.1)
            style.addLayer(labels)

            // Neutral pressure-center labels avoid conflicting with the pressure
            // fill palette, where low pressure is blue and high pressure is red.
            let centerColor = NSExpression(forConstantValue: UIColor.black)
            let centers = MLNSymbolStyleLayer(identifier: WeatherMapView.isobarCenterLayerID, source: source)
            centers.predicate = isCenter
            centers.text = NSExpression(forKeyPath: "kind")
            centers.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
            centers.textFontSize = NSExpression(forConstantValue: 24)
            centers.textColor = centerColor
            centers.textHaloColor = NSExpression(forConstantValue: UIColor.white.withAlphaComponent(0.85))
            centers.textHaloWidth = NSExpression(forConstantValue: 1.4)
            centers.textAllowsOverlap = NSExpression(forConstantValue: true)
            centers.textIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(centers)

            let centerValues = MLNSymbolStyleLayer(
                identifier: WeatherMapView.isobarCenterValueLayerID, source: source)
            centerValues.predicate = isCenter
            centerValues.text = NSExpression(forKeyPath: "label")
            centerValues.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
            centerValues.textFontSize = NSExpression(forConstantValue: 10)
            centerValues.textColor = centerColor
            centerValues.textHaloColor = NSExpression(forConstantValue: UIColor.white.withAlphaComponent(0.85))
            centerValues.textHaloWidth = NSExpression(forConstantValue: 1.2)
            centerValues.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.5)))
            centerValues.textAllowsOverlap = NSExpression(forConstantValue: true)
            centerValues.textIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(centerValues)
        }

        private func removeIsobarLayers(from style: MLNStyle) {
            for id in [WeatherMapView.isobarCenterValueLayerID, WeatherMapView.isobarCenterLayerID,
                       WeatherMapView.isobarLabelLayerID, WeatherMapView.isobarLineLayerID,
                       WeatherMapView.isobarCasingLayerID] {
                if let layer = style.layer(withIdentifier: id) { style.removeLayer(layer) }
            }
            if let source = style.source(withIdentifier: WeatherMapView.isobarSourceID) {
                style.removeSource(source)
            }
            isobarSyncKey = nil
        }

        // MARK: Storm cells

        /// Tracked precipitation cells (server `/radar/{region}/cells`), SCIT-style:
        /// the cell's footprint hull, its extrapolated one-hour track with +15-min
        /// tick marks and an arrowhead, a widening uncertainty cone, and a peak-
        /// intensity marker (the tap target). Features are rebuilt client-side from
        /// the GeoJSON properties (`path`/`footprint`), which MapLibre can't draw
        /// directly.
        private func syncStormCells(style: MLNStyle, active: Bool, region: RadarRegion) {
            guard active else {
                removeStormCellLayers(from: style)
                return
            }

            let isStale = stormCellsFetchedAt.map { Date().timeIntervalSince($0) > 120 } ?? true
            if (isStale || stormCellsRegion != region), !isLoadingStormCells {
                isLoadingStormCells = true
                Task { @MainActor [weak self] in
                    defer { self?.isLoadingStormCells = false }
                    do {
                        let data = try await APIClient.shared.getStormCells(region: region.pathComponent)
                        guard let self, !self.isTornDown else { return }
                        self.stormCells = Self.parseStormCells(data)
                        self.stormCellsFetchedAt = Date()
                        self.stormCellsRegion = region
                        if let style = self.mapView?.style {
                            self.removeStormCellLayers(from: style)
                        }
                        self.syncAll()
                    } catch {
                        mapLibreLogger.error("Storm cell fetch failed: \(error.localizedDescription, privacy: .public)")
                        // Record the attempted region too, or a failed region switch
                        // would re-trigger the fetch on every sync with no backoff.
                        self?.stormCellsFetchedAt = Date()
                        self?.stormCellsRegion = region
                    }
                }
            }

            guard style.source(withIdentifier: WeatherMapView.cellPointSourceID) == nil,
                  let cells = stormCells
            else { return }

            let features = Self.buildStormCellFeatures(cells)

            let coneSource = MLNShapeSource(
                identifier: WeatherMapView.cellConeSourceID, features: features.cones, options: nil)
            let footprintSource = MLNShapeSource(
                identifier: WeatherMapView.cellFootprintSourceID, features: features.footprints, options: nil)
            let trackSource = MLNShapeSource(
                identifier: WeatherMapView.cellTrackSourceID, features: features.tracks, options: nil)
            let tickSource = MLNShapeSource(
                identifier: WeatherMapView.cellTickSourceID, features: features.ticks, options: nil)
            let headSource = MLNShapeSource(
                identifier: WeatherMapView.cellHeadSourceID, features: features.heads, options: nil)
            let pointSource = MLNShapeSource(
                identifier: WeatherMapView.cellPointSourceID, features: features.points, options: nil)
            for source in [coneSource, footprintSource, trackSource, tickSource, headSource, pointSource] {
                style.addSource(source)
            }

            // Peak-intensity steps aligned with the radar palette's hue progression
            // (mirrored in StormCellLegend). Typed constructors — see severityColor.
            let intensityColor = NSExpression(
                forMLNStepping: NSExpression(forKeyPath: "peak_mmh"),
                from: NSExpression(forConstantValue: UIColor(red: 0, green: 0.79, blue: 0.79, alpha: 1)),  // #00caca
                stops: NSExpression(forConstantValue: [
                    2: UIColor(red: 1, green: 1, blue: 0, alpha: 1),          // moderate: #ffff00
                    10: UIColor(red: 1, green: 0, blue: 0, alpha: 1),         // heavy: #ff0000
                    50: UIColor(red: 0.996, green: 0.2, blue: 1, alpha: 1),   // extreme: #fe33ff
                ])
            )

            // Uncertainty cone: a faint wash widening along the track (hurricane-cone
            // visual language) — beneath everything else.
            let cone = MLNFillStyleLayer(identifier: WeatherMapView.cellConeLayerID, source: coneSource)
            cone.fillColor = NSExpression(forConstantValue: UIColor.white)
            cone.fillOpacity = NSExpression(forConstantValue: 0.08)
            insertOverlayLayer(cone, in: style)

            // Actual echo footprint, tinted by peak intensity.
            let footprintFill = MLNFillStyleLayer(
                identifier: WeatherMapView.cellFootprintFillLayerID, source: footprintSource)
            footprintFill.fillColor = intensityColor
            footprintFill.fillOpacity = NSExpression(forConstantValue: 0.14)
            insertOverlayLayer(footprintFill, in: style)

            let footprintLine = MLNLineStyleLayer(
                identifier: WeatherMapView.cellFootprintLineLayerID, source: footprintSource)
            footprintLine.lineColor = intensityColor
            footprintLine.lineOpacity = NSExpression(forConstantValue: 0.8)
            footprintLine.lineWidth = NSExpression(forConstantValue: 1.3)
            insertOverlayLayer(footprintLine, in: style)

            let track = MLNLineStyleLayer(identifier: WeatherMapView.cellTrackLayerID, source: trackSource)
            track.lineColor = NSExpression(forConstantValue: UIColor.white)
            track.lineOpacity = NSExpression(forConstantValue: 0.75)
            track.lineWidth = NSExpression(forConstantValue: 1.8)
            track.lineDashPattern = NSExpression(forConstantValue: [1.8, 1.6])
            track.lineCap = NSExpression(forConstantValue: "round")
            insertOverlayLayer(track, in: style)

            // +15-min tick dots along the track.
            let ticks = MLNCircleStyleLayer(identifier: WeatherMapView.cellTickLayerID, source: tickSource)
            ticks.circleColor = NSExpression(forConstantValue: UIColor.white)
            ticks.circleRadius = NSExpression(forConstantValue: 2.4)
            ticks.circleOpacity = NSExpression(forConstantValue: 0.95)
            ticks.circleStrokeColor = NSExpression(forConstantValue: UIColor.black)
            ticks.circleStrokeWidth = NSExpression(forConstantValue: 0.75)
            ticks.circleStrokeOpacity = NSExpression(forConstantValue: 0.25)
            insertOverlayLayer(ticks, in: style)

            let circles = MLNCircleStyleLayer(identifier: WeatherMapView.cellCircleLayerID, source: pointSource)
            circles.circleColor = intensityColor
            circles.circleRadius = NSExpression(
                forMLNStepping: NSExpression(forKeyPath: "area_km2"),
                from: NSExpression(forConstantValue: 4.5),
                stops: NSExpression(forConstantValue: [80: 6, 300: 7.5])
            )
            circles.circleOpacity = NSExpression(forConstantValue: 0.9)
            circles.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            circles.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
            insertOverlayLayer(circles, in: style)

            // Arrowhead + tick labels read ABOVE the map labels, like the motion arrows.
            if style.image(forName: WeatherMapView.cellArrowImageName) == nil {
                style.setImage(RadarArrowGeometry.arrowImage(), forName: WeatherMapView.cellArrowImageName)
            }
            let heads = MLNSymbolStyleLayer(identifier: WeatherMapView.cellHeadLayerID, source: headSource)
            heads.iconImageName = NSExpression(forConstantValue: WeatherMapView.cellArrowImageName)
            heads.iconRotation = NSExpression(forKeyPath: "rotation")
            heads.iconScale = NSExpression(forConstantValue: 0.7)
            heads.iconRotationAlignment = NSExpression(forConstantValue: "map")
            heads.iconAllowsOverlap = NSExpression(forConstantValue: true)
            heads.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            heads.iconOpacity = NSExpression(forConstantValue: 0.9)
            style.addLayer(heads)

            let tickLabels = MLNSymbolStyleLayer(
                identifier: WeatherMapView.cellTickLabelLayerID, source: tickSource)
            tickLabels.text = NSExpression(forKeyPath: "label")
            // The ONLY font stack the OpenFreeMap styles serve glyphs for.
            tickLabels.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
            tickLabels.textFontSize = NSExpression(forConstantValue: 10)
            tickLabels.textColor = NSExpression(forConstantValue: UIColor.white)
            tickLabels.textHaloColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.55))
            tickLabels.textHaloWidth = NSExpression(forConstantValue: 1)
            tickLabels.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: -1.1)))
            tickLabels.textAllowsOverlap = NSExpression(forConstantValue: false)
            style.addLayer(tickLabels)
        }

        private func removeStormCellLayers(from style: MLNStyle) {
            for id in [WeatherMapView.cellHeadLayerID, WeatherMapView.cellTickLabelLayerID,
                       WeatherMapView.cellCircleLayerID, WeatherMapView.cellTickLayerID,
                       WeatherMapView.cellTrackLayerID, WeatherMapView.cellFootprintLineLayerID,
                       WeatherMapView.cellFootprintFillLayerID, WeatherMapView.cellConeLayerID] {
                if let layer = style.layer(withIdentifier: id) { style.removeLayer(layer) }
            }
            for id in [WeatherMapView.cellPointSourceID, WeatherMapView.cellTrackSourceID,
                       WeatherMapView.cellConeSourceID, WeatherMapView.cellFootprintSourceID,
                       WeatherMapView.cellTickSourceID, WeatherMapView.cellHeadSourceID] {
                if let source = style.source(withIdentifier: id) { style.removeSource(source) }
            }
        }

        private struct StormCellsGeoJSON: Decodable {
            struct Feature: Decodable {
                struct Geometry: Decodable { let coordinates: [Double] }
                struct Properties: Decodable {
                    let id: Int
                    let area_km2: Double
                    let peak_mmh: Double
                    let mean_mmh: Double?
                    let velocity_kmh: Double
                    let bearing_deg: Double?
                    let path: [[Double]]
                    let footprint: [[Double]]?
                }
                let geometry: Geometry
                let properties: Properties
            }
            let features: [Feature]
        }

        private static func parseStormCells(_ data: Data) -> [StormCellInfo] {
            guard let collection = try? JSONDecoder().decode(StormCellsGeoJSON.self, from: data) else {
                return []
            }
            return collection.features.compactMap { feature in
                guard feature.geometry.coordinates.count == 2 else { return nil }
                func coordinate(_ pair: [Double]) -> CLLocationCoordinate2D? {
                    pair.count == 2
                        ? CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0]) : nil
                }
                return StormCellInfo(
                    id: feature.properties.id,
                    center: CLLocationCoordinate2D(
                        latitude: feature.geometry.coordinates[1],
                        longitude: feature.geometry.coordinates[0]),
                    areaKm2: feature.properties.area_km2,
                    peakMmh: feature.properties.peak_mmh,
                    meanMmh: feature.properties.mean_mmh ?? feature.properties.peak_mmh,
                    velocityKmh: feature.properties.velocity_kmh,
                    bearingDeg: feature.properties.bearing_deg ?? 0,
                    path: feature.properties.path.compactMap(coordinate),
                    footprint: (feature.properties.footprint ?? []).compactMap(coordinate))
            }
        }

        private struct StormCellFeatureSet {
            var points: [MLNPointFeature] = []
            var tracks: [MLNPolylineFeature] = []
            var cones: [MLNPolygonFeature] = []
            var footprints: [MLNPolygonFeature] = []
            var ticks: [MLNPointFeature] = []
            var heads: [MLNPointFeature] = []
        }

        /// Rebuilds the overlay geometry from the parsed cells: marker points, track
        /// polylines with +15-min ticks and an end arrowhead, footprint hull polygons
        /// and the widening uncertainty cone (half-width = footprint radius growing
        /// ~18% of the distance traveled — honest about extrapolation error).
        private static func buildStormCellFeatures(_ cells: [StormCellInfo]) -> StormCellFeatureSet {
            var set = StormCellFeatureSet()
            for cell in cells {
                let point = MLNPointFeature()
                point.coordinate = cell.center
                point.attributes = [
                    "cell_id": cell.id,
                    "peak_mmh": cell.peakMmh,
                    "area_km2": cell.areaKm2,
                ]
                set.points.append(point)

                if cell.footprint.count >= 4 {
                    var ring = cell.footprint
                    let footprint = MLNPolygonFeature(
                        coordinates: &ring, count: UInt(ring.count), interiorPolygons: nil)
                    footprint.attributes = ["cell_id": cell.id, "peak_mmh": cell.peakMmh]
                    set.footprints.append(footprint)
                }

                // Track features only for cells that actually move — a stationary
                // cell's "track" would be a dot pile with a random arrowhead.
                var trackPoints = [cell.center] + cell.path
                guard cell.velocityKmh >= 3, trackPoints.count >= 2 else { continue }

                let track = MLNPolylineFeature(
                    coordinates: &trackPoints, count: UInt(trackPoints.count))
                set.tracks.append(track)

                for (index, position) in cell.path.enumerated() {
                    let tick = MLNPointFeature()
                    tick.coordinate = position
                    let minutes = 15 * (index + 1)
                    // Label only +30/+60 — every tick labeled reads as clutter.
                    // ASCII apostrophe: the OpenFreeMap glyph ranges may not carry U+2032.
                    tick.attributes = ["label": minutes % 30 == 0 ? "+\(minutes)'" : ""]
                    set.ticks.append(tick)
                }

                let last = trackPoints[trackPoints.count - 1]
                let previous = trackPoints[trackPoints.count - 2]
                let direction = kmVector(from: previous, to: last)
                let head = MLNPointFeature()
                head.coordinate = last
                head.attributes = [
                    "rotation": atan2(direction.x, direction.y) * 180 / .pi,
                ]
                set.heads.append(head)

                if let cone = conePolygon(for: cell, trackPoints: trackPoints) {
                    set.cones.append(cone)
                }
            }
            return set
        }

        /// Uncertainty cone around the projected track: left/right offsets whose
        /// half-width starts at the footprint radius and grows with distance.
        private static func conePolygon(
            for cell: StormCellInfo, trackPoints: [CLLocationCoordinate2D]
        ) -> MLNPolygonFeature? {
            let baseWidth = max(2.0, cell.radiusKm)
            var left: [CLLocationCoordinate2D] = []
            var right: [CLLocationCoordinate2D] = []
            var traveled = 0.0
            for index in trackPoints.indices {
                let incoming = index > 0
                    ? kmVector(from: trackPoints[index - 1], to: trackPoints[index])
                    : kmVector(from: trackPoints[0], to: trackPoints[1])
                let outgoing = index < trackPoints.count - 1
                    ? kmVector(from: trackPoints[index], to: trackPoints[index + 1])
                    : incoming
                if index > 0 { traveled += (incoming.x * incoming.x + incoming.y * incoming.y).squareRoot() }
                // Averaged direction at interior vertices keeps the cone smooth.
                let dx = incoming.x + outgoing.x, dy = incoming.y + outgoing.y
                let length = (dx * dx + dy * dy).squareRoot()
                guard length > 0.01 else { return nil }
                let normal = (x: -dy / length, y: dx / length)
                let halfWidth = baseWidth + 0.18 * traveled
                left.append(offset(trackPoints[index], eastKm: normal.x * halfWidth,
                                   northKm: normal.y * halfWidth))
                right.append(offset(trackPoints[index], eastKm: -normal.x * halfWidth,
                                    northKm: -normal.y * halfWidth))
            }
            guard traveled >= baseWidth else { return nil }   // barely moves → no cone
            var ring = left + right.reversed()
            ring.append(ring[0])
            return MLNPolygonFeature(coordinates: &ring, count: UInt(ring.count), interiorPolygons: nil)
        }

        /// Local flat-earth kilometers from `a` to `b` (fine at storm-track scale).
        private static func kmVector(
            from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D
        ) -> (x: Double, y: Double) {
            let midLat = (a.latitude + b.latitude) / 2 * .pi / 180
            return ((b.longitude - a.longitude) * 111.320 * cos(midLat),
                    (b.latitude - a.latitude) * 110.574)
        }

        private static func offset(
            _ base: CLLocationCoordinate2D, eastKm: Double, northKm: Double
        ) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: base.latitude + northKm / 110.574,
                longitude: base.longitude + eastKm
                    / (111.320 * max(0.2, cos(base.latitude * .pi / 180))))
        }

        // MARK: Feature tap-through (warnings + storm cells)

        /// Query the tapped point's rendered features: cells win (small targets, padded
        /// hit box), then every warning polygon under the finger — deduped by alert id
        /// (MultiPolygon parts return one feature each) and sorted most severe first.
        @objc fileprivate func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let mapView else { return }
            let point = gesture.location(in: mapView)

            let pad: CGFloat = 22
            let hitBox = CGRect(x: point.x - pad, y: point.y - pad, width: pad * 2, height: pad * 2)
            let cellHit = mapView
                .visibleFeatures(in: hitBox, styleLayerIdentifiers: [
                    WeatherMapView.cellCircleLayerID, WeatherMapView.cellFootprintFillLayerID,
                ])
                .compactMap { feature -> StormCellInfo? in
                    guard let id = feature.attributes["cell_id"] as? Int else { return nil }
                    return stormCells?.first { $0.id == id }
                }
                .first
            if let cellHit, let onCellTapped = parent.onCellTapped {
                UIApplication.shared.playHapticFeedback()
                onCellTapped(cellHit)
                return
            }

            guard let onAlertsTapped = parent.onAlertsTapped else { return }
            var seen = Set<String>()
            var alerts: [WeatherAlertInfo] = []
            for feature in mapView.visibleFeatures(
                at: point, styleLayerIdentifiers: [WeatherMapView.alertFillLayerID]) {
                guard let info = WeatherAlertInfo(attributes: feature.attributes),
                      seen.insert(info.id).inserted else { continue }
                alerts.append(info)
            }
            guard !alerts.isEmpty else { return }
            alerts.sort { $0.severityRank > $1.severityRank }
            UIApplication.shared.playHapticFeedback()
            onAlertsTapped(alerts)
        }

        private func removeAlertPolygonLayers(from style: MLNStyle) {
            if let layer = style.layer(withIdentifier: WeatherMapView.alertFillLayerID) {
                style.removeLayer(layer)
            }
            if let layer = style.layer(withIdentifier: WeatherMapView.alertOutlineLayerID) {
                style.removeLayer(layer)
            }
            if let source = style.source(withIdentifier: WeatherMapView.alertSourceID) {
                style.removeSource(source)
            }
        }

        // MARK: Wind particles

        private func syncWindParticles(selection: WeatherTileLayer?, state: ModelGridLayerState?) {
            guard let particleView = windParticleView else { return }
            let isWindLayer = parent.showWindParticles
                && (selection == .iconWind || selection == .gfsWind)

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
                    Task { await WindFieldCache.shared.evict(retaining: keepIds) }
                }
            }

            particleView.isHidden = UIAccessibility.isReduceMotionEnabled
            if !UIAccessibility.isReduceMotionEnabled {
                particleView.startDisplayLinkIfNeeded()
            }
        }

        // MARK: City value bubbles (model temperature + wind layers)

        /// Value badges sampled from the CURRENT grid at a curated city list:
        /// bubble fill = the palette color of the sampled index, label = the value
        /// in the user's unit. Same data + same palette as the raster behind it,
        /// so the bubbles double as a legend-in-context.
        ///
        /// NO collision system: three rank layers gated by zoom with
        /// allowsOverlap + ignoresPlacement. Collision placement fades symbols in
        /// over ~300 ms, which made every bubble FLASH on each scrub step —
        /// placement-less symbols swap content instantly.
        private static let bubbleSourceID = "oscar-value-bubbles"
        private static let bubbleRankMinZooms: [Float] = [2.5, 4.5, 6.0]

        private func syncValueBubbles(style: MLNStyle, selection: WeatherTileLayer?, enabled: Bool,
                                      payload: RadarGridPayload?, frameKey: String?) {
            let isBubbleLayer: Bool
            switch selection {
            case .iconTemp, .gfsTemp, .iconWind, .gfsWind: isBubbleLayer = true
            default: isBubbleLayer = false
            }
            guard isBubbleLayer, enabled, let selection, let payload, let frameKey,
                  let bounds = parent.modelGridState?.bounds,
                  let palette = modelPalette, modelPaletteId == selection.colormapId else {
                if bubbleSyncKey != nil {
                    removeValueBubbles(from: style)
                }
                return
            }

            let isWind = selection == .iconWind || selection == .gfsWind
            let unit = isWind
                ? parent.settingsService.windSpeedUnit
                : parent.settingsService.temperatureUnit

            // The location indicator (blue dot / selected city) must stay
            // readable — drop bubbles that would stack on top of it. The bubbles
            // ignore symbol placement, so MapLibre would happily draw both.
            var indicatorAnchors = [parent.coordinates]
            if let userCoordinate = mapView?.userLocation?.location?.coordinate {
                indicatorAnchors.append(userCoordinate)
            }
            func nearIndicator(lat: Double, lon: Double) -> Bool {
                indicatorAnchors.contains { anchor in
                    let dLatKm = (anchor.latitude - lat) * 111.32
                    let dLonKm = (anchor.longitude - lon) * 111.32 * cos(lat * .pi / 180)
                    return dLatKm * dLatKm + dLonKm * dLonKm < 12 * 12
                }
            }
            let anchorKey = indicatorAnchors
                .map { String(format: "%.2f,%.2f", $0.latitude, $0.longitude) }
                .joined(separator: ";")
            let syncKey = "\(selection.rawValue)|\(frameKey)|\(unit)|\(anchorKey)"
            guard bubbleSyncKey != syncKey else { return }

            var features: [MLNPointFeature] = []
            var signature = ""
            features.reserveCapacity(MapValueBubbles.bubbleCities.count)
            for city in MapValueBubbles.bubbleCities {
                guard !nearIndicator(lat: city.lat, lon: city.lon) else { continue }
                guard let index = MapValueBubbles.sampleGridIndex(
                    payload: payload, bounds: bounds, lat: city.lat, lon: city.lon) else { continue }
                // Inverse of the server's linear grid spans (Colormaps.gridIndex):
                // temperature maxValue 90 shift 40, wind_speed maxValue 50 shift 0.
                let label: String
                if isWind {
                    let mps = (Double(index) - 1) / 254 * 50
                    label = MapValueBubbles.windLabel(metersPerSecond: mps, unit: unit)
                } else {
                    let celsius = (Double(index) - 1) / 254 * 90 - 40
                    let shown = unit == "fahrenheit" ? celsius * 9 / 5 + 32 : celsius
                    label = "\(Int(shown.rounded()))°"
                }

                // One icon per ~6-index palette bucket, registered lazily. The name
                // carries the colormap id — buckets mean different colors per layer.
                let bucket = min(255, (Int(index) / 6) * 6 + 3)
                let iconName = "oscar-bubble-\(selection.colormapId)-\(bucket)"
                if !registeredBubbleIcons.contains(iconName) {
                    let entry = palette[bucket]
                    let color = UIColor(red: CGFloat(entry.r) / 255, green: CGFloat(entry.g) / 255,
                                        blue: CGFloat(entry.b) / 255, alpha: 1)
                    style.setImage(MapValueBubbles.bubbleImage(color: color), forName: iconName)
                    registeredBubbleIcons.insert(iconName)
                }

                let feature = MLNPointFeature()
                feature.coordinate = CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
                feature.attributes = [
                    "icon": iconName,
                    "label": label,
                    "rank": city.rank,
                ]
                features.append(feature)
                signature += "\(iconName)|\(label);"
            }

            ensureValueBubbleLayers(in: style)
            // Scrubbing adjacent hours often changes nothing visible at bubble
            // precision — skip the source swap entirely then.
            if signature != lastBubbleSignature {
                (style.source(withIdentifier: Self.bubbleSourceID) as? MLNShapeSource)?
                    .shape = MLNShapeCollectionFeature(shapes: features)
                lastBubbleSignature = signature
            }
            bubbleSyncKey = syncKey
        }

        /// One shared source + one symbol layer per rank tier. Density comes from
        /// the tiers' minimum zoom levels, not from collision (see syncValueBubbles).
        private func ensureValueBubbleLayers(in style: MLNStyle) {
            guard style.source(withIdentifier: Self.bubbleSourceID) == nil else { return }
            let source = MLNShapeSource(identifier: Self.bubbleSourceID,
                                        shape: MLNShapeCollectionFeature(shapes: []))
            style.addSource(source)
            for (rank, minZoom) in Self.bubbleRankMinZooms.enumerated() {
                let layer = MLNSymbolStyleLayer(
                    identifier: "\(Self.bubbleSourceID)-r\(rank)", source: source)
                layer.predicate = NSPredicate(format: "rank == %d", rank)
                layer.minimumZoomLevel = minZoom
                layer.iconImageName = NSExpression(forKeyPath: "icon")
                layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
                layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
                layer.text = NSExpression(forKeyPath: "label")
                // The ONLY font stack the OpenFreeMap styles serve glyphs for — the
                // default Open Sans stack would 404 and the labels would vanish.
                layer.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
                layer.textFontSize = NSExpression(forConstantValue: 11)
                layer.textColor = NSExpression(forConstantValue: UIColor.white)
                layer.textHaloColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.45))
                layer.textHaloWidth = NSExpression(forConstantValue: 1)
                layer.textAllowsOverlap = NSExpression(forConstantValue: true)
                layer.textIgnoresPlacement = NSExpression(forConstantValue: true)
                style.addLayer(layer)   // topmost — value badges read above the labels
            }
        }

        private func removeValueBubbles(from style: MLNStyle) {
            for rank in Self.bubbleRankMinZooms.indices {
                if let layer = style.layer(withIdentifier: "\(Self.bubbleSourceID)-r\(rank)") {
                    style.removeLayer(layer)
                }
            }
            if let source = style.source(withIdentifier: Self.bubbleSourceID) {
                style.removeSource(source)
            }
            bubbleSyncKey = nil
            lastBubbleSignature = nil
            registeredBubbleIcons.removeAll()
        }

        // MARK: Annotations

        /// iOS-style marker replica for the selected city (MapLibre's default is the
        /// legacy pin): red balloon, white location glyph, tip anchored on the spot.
        /// (Delegate callbacks arrive on the main thread; the `nonisolated(unsafe)`
        /// locals only ferry the non-Sendable return out of `assumeIsolated`.)
        nonisolated func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
            nonisolated(unsafe) var result: MLNAnnotationImage?
            nonisolated(unsafe) let annotation = annotation
            MainActor.assumeIsolated {
                guard !(annotation is MLNUserLocation) else { return }
                result = mapView.dequeueReusableAnnotationImage(withIdentifier: "selected-city-marker")
                    ?? MLNAnnotationImage(image: Self.markerImage(), reuseIdentifier: "selected-city-marker")
            }
            return result
        }

        nonisolated func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            nonisolated(unsafe) var result: MLNAnnotationView?
            nonisolated(unsafe) let annotation = annotation
            MainActor.assumeIsolated {
                guard annotation is MLNUserLocation else { return }
                // Empty view suppresses the stock puck: view-based annotations lag
                // one display frame behind the basemap during gestures. The visible
                // dot renders in-style instead (UserLocationDot, syncUserLocationDot).
                result = MLNUserLocationAnnotationView(reuseIdentifier: "user-location-hidden")
            }
            return result
        }

        // MARK: User location dot (style layers)

        nonisolated func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
            MainActor.assumeIsolated {
                guard let style = mapView.style else { return }
                syncUserLocationDot(style: style)
            }
        }

        private func syncUserLocationDot(style: MLNStyle) {
            UserLocationDot.sync(style: style, coordinate: mapView?.userLocation?.coordinate)

            // Pulse only on the fullscreen map: each beat animates paint
            // transitions, which keeps the map render loop busy — too costly for
            // the always-on NowView preview card.
            let wantsPulse = parent.userActionAllowed && !UIAccessibility.isReduceMotionEnabled
            if wantsPulse, userDotPulseTimer == nil {
                userDotPulseTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, !self.isTornDown, let style = self.mapView?.style else { return }
                        UserLocationDot.pulseBeat(style: style)
                    }
                }
            } else if !wantsPulse {
                userDotPulseTimer?.invalidate()
                userDotPulseTimer = nil
            }
        }

        /// The selected-city marker (`SelectedCityMarker` asset, 534×652 with the
        /// balloon tip at 97.4% height). The canvas is twice the tip's y so the
        /// CENTER-anchored MLNAnnotationImage pins the tip on the coordinate.
        private static func markerImage() -> UIImage {
            let displaySize = CGSize(width: 34, height: 34 * 652 / 534)
            let tipY = displaySize.height * (635.0 / 652.0)
            let canvas = CGSize(width: displaySize.width, height: tipY * 2)
            let asset = UIImage(named: "SelectedCityMarker")
            return UIGraphicsImageRenderer(size: canvas).image { _ in
                asset?.draw(in: CGRect(origin: .zero, size: displaySize))
            }
        }

        private func syncSelectedCityAnnotation() {
            guard let mapView else { return }
            let selectedCity = parent.cities.first(where: \.selected)

            guard let selectedCity else {
                if let existing = selectedCityAnnotation {
                    mapView.removeAnnotation(existing)
                    selectedCityAnnotation = nil
                    selectedCityIdentity = nil
                }
                return
            }

            let identity = "\(selectedCity.label)|\(selectedCity.lat)|\(selectedCity.lon)"
            guard selectedCityIdentity != identity else { return }
            if let existing = selectedCityAnnotation {
                mapView.removeAnnotation(existing)
            }
            let annotation = MLNPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: selectedCity.lat, longitude: selectedCity.lon)
            annotation.title = selectedCity.label
            mapView.addAnnotation(annotation)
            selectedCityAnnotation = annotation
            selectedCityIdentity = identity
        }

        // MARK: Helpers

        /// Overlay layers (radar, model image) sit above ALL geometry
        /// (roads included — "below the first symbol layer" landed under the streets:
        /// the dark style's first symbol is a water label that sits below the road
        /// lines), below the trailing labels.
        private func insertOverlayLayer(_ layer: MLNStyleLayer, in style: MLNStyle) {
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

// MARK: - Basemap attribution

/// ODbL/OpenMapTiles credit for the OpenFreeMap basemap. Initially visible in
/// the map corner, then auto-fades after 5 s — one of the collapse mechanisms
/// the OSMF attribution guidelines explicitly sanction, provided the credit
/// stays findable afterwards (LegalView's OpenStreetMap/OpenFreeMap entries).
/// MapLibre's ⓘ button stays hidden; this label replaces it.
struct MapAttributionLabel: View {
    @State private var visible = true

    var body: some View {
        Text(verbatim: "© OpenMapTiles © OpenStreetMap")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .shadow(color: .black.opacity(0.4), radius: 1)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.8)) {
                    visible = false
                }
            }
    }
}
