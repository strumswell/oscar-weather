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
//  images (MLNImageSource), RainViewer tiles, wind particles (sibling Metal-free
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

    /// OpenFreeMap Fiord — dark basemap (matches the app, radar colors pop).
    /// No API key; `dark` and `positron` (light) are the alternatives.
    private static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/fiord")!
    fileprivate static let radarLayerID = "oscar-radar-layer"
    fileprivate static let modelLayerID = "oscar-model-image"
    fileprivate static let rainviewerLayerID = "rainviewer-radar"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: Self.styleURL)
        mapLibreLogger.info("map view created role=\(userActionAllowed ? "fullscreen" : "preview", privacy: .public)")
        mapView.delegate = context.coordinator
        mapView.setCenter(coordinates, zoomLevel: 7, animated: false)
        mapView.allowsTilting = false
        mapView.showsUserLocation = true
        // OpenFreeMap/OSM (ODbL) attribution lives behind MapLibre's ⓘ button; only
        // the wordmark is hidden.
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = !userActionAllowed
        if !userActionAllowed {
            mapView.allowsScrolling = false
            mapView.allowsZooming = false
            mapView.allowsRotating = false
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

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncAll()

        // Static (non-interactive) previews follow the selected location.
        if !userActionAllowed {
            let current = mapView.centerCoordinate
            let distance = CLLocation(latitude: current.latitude, longitude: current.longitude)
                .distance(from: CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude))
            if distance > 1000 {
                mapView.setCenter(coordinates, zoomLevel: 7, animated: false)
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

        private var rainviewerTemplate: String?
        private var isLoadingRainviewer = false

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

            let radarState = parent.oscarRadarState
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
            // Observation re-arm reads (not passed anywhere): currentLayer and the
            // frame indices must be read HERE so withObservationTracking re-fires
            // syncAll when they change — currentFrame/currentFrameKey read them
            // behind guards that can hide them from the tracker on some paths.
            _ = gfsState?.currentLayer
            _ = gfsState?.renderFrameIndex
            _ = gfsState?.currentFrameIndex

            guard let style = mapView?.style else { return blocked("style not loaded") }
            blocked(nil)

            syncRadar(style: style, active: radarActive, state: radarState, bounds: radarBounds,
                      frame: radarFrame, next: radarNext, renderedIndex: radarRenderedIndex,
                      loadedCount: radarLoadedCount, frameCount: radarFrameCount,
                      isPlaying: radarIsPlaying, motion: radarMotion, smoothMotion: smoothMotion,
                      softRendering: softRendering, arrowsEnabled: motionArrows)
            syncModelLayer(style: style, selection: activeTileLayer, state: gfsState,
                           bounds: gfsBounds, payload: gfsFrame, frameKey: gfsFrameKey,
                           next: gfsNext, isPlaying: gfsIsPlaying,
                           smoothMotion: smoothMotion, softRendering: softRendering)
            syncValueBubbles(style: style, selection: activeTileLayer, enabled: valueBubbles,
                             payload: gfsFrame, frameKey: gfsFrameKey)
            syncRainviewer(style: style,
                           active: settings.settings?.rainviewerLayer == true
                               && !radarActive && activeTileLayer == nil)
            syncWindParticles(selection: activeTileLayer, state: gfsState)
            syncSelectedCityAnnotation()
            syncUserLocationDot(style: style)
        }

        // MARK: Radar (custom layer + motion morph + arrows)

        private func syncRadar(
            style: MLNStyle, active: Bool, state: OscarRadarState?,
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
            layer.setSoftRendering(softRendering)
            layer.setMotion(motion)

            if !layer.hasPalette, !isFetchingPalette {
                isFetchingPalette = true
                Task { @MainActor [weak self, weak layer] in
                    let palette = await OscarRadarState.resolvedPalette()
                    layer?.setPalette(palette)
                    layer?.setNeedsDisplay()
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
                style.setImage(RadarMotionArrows.arrowImage(), forName: Self.arrowImageName)
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
            smoothMotion: Bool, softRendering: Bool
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
            layer.setSoftRendering(softRendering)

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
                    guard let palette = await ModelGridLayerState.palette(for: colormapId) else { return }
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
                // cross-fade in data space); the state's 0.8 s Timer would
                // double-advance, so it is cancelled while the layer runs.
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
            layer.display(frameA: textureA, frameB: textureB)
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

        // MARK: RainViewer tiles

        private func syncRainviewer(style: MLNStyle, active: Bool) {
            let id = WeatherMapView.rainviewerLayerID
            guard active else {
                if style.layer(withIdentifier: id) != nil || style.source(withIdentifier: id) != nil {
                    if let layer = style.layer(withIdentifier: id) { style.removeLayer(layer) }
                    if let source = style.source(withIdentifier: id) { style.removeSource(source) }
                }
                rainviewerTemplate = nil
                return
            }
            if style.source(withIdentifier: id) != nil { return }

            if let template = rainviewerTemplate {
                let source = MLNRasterTileSource(
                    identifier: id, tileURLTemplates: [template], options: [.tileSize: 256])
                let layer = MLNRasterStyleLayer(identifier: id, source: source)
                layer.rasterOpacity = NSExpression(forConstantValue: parent.overlayOpacity)
                style.addSource(source)
                insertOverlayLayer(layer, in: style)
                return
            }
            guard !isLoadingRainviewer else { return }
            isLoadingRainviewer = true
            Task { @MainActor [weak self] in
                defer { self?.isLoadingRainviewer = false }
                do {
                    let data = try await APIClient.shared.getRainViewerMaps()
                    let host = data.host ?? "https://tilecache.rainviewer.com"
                    guard let path = data.radar?.past?.last?.path else { return }
                    self?.rainviewerTemplate = "\(host)\(path)/256/{z}/{x}/{y}/4/1_1.png"
                    self?.syncAll()
                } catch {
                    mapLibreLogger.error("RainViewer template fetch failed: \(error.localizedDescription, privacy: .public)")
                }
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
                ? (parent.settingsService.settings?.windSpeedUnit ?? "kmh")
                : (parent.settingsService.settings?.temperatureUnit ?? "celsius")
            let syncKey = "\(selection.rawValue)|\(frameKey)|\(unit)"
            guard bubbleSyncKey != syncKey else { return }

            var features: [MLNPointFeature] = []
            var signature = ""
            features.reserveCapacity(MapValueBubbles.bubbleCities.count)
            for city in MapValueBubbles.bubbleCities {
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

        /// Overlay layers (radar, model image, RainViewer) sit above ALL geometry
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
