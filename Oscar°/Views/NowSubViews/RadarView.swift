//
//  RadarView.swift
//  Weather
//
//  Created by Philipp Bolte on 11.08.21.
//

import MapKit
import SwiftUI
import UIKit

struct RadarView: View {
    @Environment(Location.self) private var location: Location
    @ObservedObject var settingsService: SettingService
    @State private var lastRefresh = Date()
    var showLayerSettings: Bool
    var locationService = LocationService.shared
    var userActionAllowed = true
    var showWindParticles = true
    var oscarRadarState: OscarRadarState?
    var gfsImageState: GFSImageLayerState?

    var body: some View {
        ZStack {
            RadarMapView(
                settingsService: settingsService,
                overlayOpacity: 0.7,
                coordinates: location.coordinates,
                cities: locationService.city.cities,
                userActionAllowed: userActionAllowed,
                showWindParticles: showWindParticles,
                lastRefresh: lastRefresh,
                oscarRadarState: oscarRadarState,
                gfsImageState: gfsImageState
            )

            // Timestamp badge + optional colormap legend — top-left
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        if settingsService.oscarRadarLayer {
                            let _ = oscarRadarState?.currentFrameIndex
                            let _ = oscarRadarState?.currentFrame
                            let _ = oscarRadarState?.nextFrame
                            let _ = oscarRadarState?.loadingFrameIndices
                            let _ = oscarRadarState?.isLoading
                            let _ = oscarRadarState?.bounds
                            if let oscarRadarState,
                               oscarRadarState.hasAnyLoadedFrame,
                               let timestamp = oscarRadarState.currentFrameTimestamp {
                            RadarTimestampBadge(
                                timestamp: timestamp,
                                isLive: oscarRadarState.isCurrentFrameLive
                            )
                            if showLayerSettings {
                                ColormapVerticalLegend(colormap: .radar)
                            }
                            } else if oscarRadarState?.isLoading == true {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        } else if settingsService.activeTileLayer != nil {
                            // Observe so updateUIView fires as images load/scrub.
                            let _ = gfsImageState?.frames.count
                            let _ = gfsImageState?.isLoading
                            let _ = gfsImageState?.currentFrameIndex
                            let _ = gfsImageState?.currentFrame
                            let _ = gfsImageState?.nextFrame
                            let _ = gfsImageState?.bounds
                            let _ = gfsImageState?.currentLayer
                            if let gfsImageState, gfsImageState.hasCurrentFrame,
                               let ts = gfsImageState.currentFrameTimestamp {
                                RadarTimestampBadge(timestamp: ts, isLive: false)
                                if showLayerSettings, let cm = settingsService.activeTileLayer?.colormap {
                                    ColormapVerticalLegend(colormap: cm)
                                }
                            } else if gfsImageState?.isLoading == true {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .padding(12)
                    Spacer()
                }
                Spacer()
            }

            if showLayerSettings {
                VStack {
                    HStack {
                        Spacer()
                        layerMenu
                    }
                    Spacer()
                }
                .padding(.trailing)
                .padding(.top)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            lastRefresh = Date()
        }
    }

    // MARK: - Layer menu

    @ViewBuilder
    private var layerMenu: some View {
        Menu {
            // ── Zentraleuropa (DWD) ────────────────────────────────────────
            Section("Zentraleuropa (DWD Radar)") {
                layerButton("Regenradar", isActive: settingsService.oscarRadarLayer) {
                    activateDWDRadar()
                }
            }
            
            // ── Zentraleuropa (DWD) ────────────────────────────────────────
            Section("Zentraleuropa (DWD ICON-D2)") {
                layerButton("Regenvorhersage",
                            isActive: settingsService.activeTileLayer == .iconPrecip) {
                    activateTileLayer(.iconPrecip)
                }
                layerButton("Temperaturvorhersage",
                            isActive: settingsService.activeTileLayer == .iconTemp) {
                    activateTileLayer(.iconTemp)
                }
                layerButton("Windvorhersage",
                            isActive: settingsService.activeTileLayer == .iconWind) {
                    activateTileLayer(.iconWind)
                }
            }

            // ── Global (GFS) ───────────────────────────────────────────────
            Section("Global (NOAA GFS)") {
                layerButton("Regenvorhersage",
                            isActive: settingsService.activeTileLayer == .gfsPrecip) {
                    activateTileLayer(.gfsPrecip)
                }
                layerButton("Temperaturvorhersage",
                            isActive: settingsService.activeTileLayer == .gfsTemp) {
                    activateTileLayer(.gfsTemp)
                }
                layerButton("Windvorhersage",
                            isActive: settingsService.activeTileLayer == .gfsWind) {
                    activateTileLayer(.gfsWind)
                }
            }

            
            // ── Rainviewer ─────────────────────────────────────────────────
            Section("Rainviewer") {
                layerButton("Regen",
                            isActive: settingsService.settings?.rainviewerLayer == true
                                   && !settingsService.oscarRadarLayer
                                   && settingsService.activeTileLayer == nil)
                {
                    activateRainviewer()
                }
            }
        } label: {
            Image(systemName: "map.fill")
                .resizable()
                .frame(width: 25, height: 25)
                .foregroundColor(.gray.opacity(0.9))
                .padding(8)
                .glassEffect(in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func layerButton(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isActive {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    // MARK: - Activation helpers

    private var isAnyLayerActive: Bool {
        settingsService.oscarRadarLayer
            || settingsService.activeTileLayer != nil
            || settingsService.settings?.rainviewerLayer == true
    }

    private func deactivateAll() {
        settingsService.oscarRadarLayer = false
        settingsService.activeTileLayer = nil
        settingsService.settings?.rainviewerLayer = false
        settingsService.save()
        oscarRadarState?.pause()
        gfsImageState?.pause()
    }

    private func activateRainviewer() {
        settingsService.oscarRadarLayer = false
        settingsService.activeTileLayer = nil
        settingsService.settings?.rainviewerLayer = true
        settingsService.settings?.dwdLayer = false
        settingsService.save()
        oscarRadarState?.pause()
        gfsImageState?.pause()
    }

    private func activateDWDRadar() {
        settingsService.activeTileLayer = nil
        settingsService.settings?.rainviewerLayer = false
        settingsService.settings?.dwdLayer = false
        settingsService.save()
        settingsService.oscarRadarLayer = true
        gfsImageState?.pause()
    }

    private func activateTileLayer(_ layer: WeatherTileLayer) {
        settingsService.oscarRadarLayer = false
        settingsService.settings?.rainviewerLayer = false
        settingsService.settings?.dwdLayer = false
        settingsService.save()
        oscarRadarState?.pause()
        settingsService.activeTileLayer = layer
    }
}

struct WebMapServiceConstants {
    static let baseUrl = "https://maps.dwd.de/geoserver/dwd/wms"
    static let version = "1.3.0"
    static let epsg = "4326"
    static let format = "image/png"
    static let tileSize = "256"
    static let transparent = true
}

struct RadarMapView: UIViewRepresentable {
    @ObservedObject var settingsService: SettingService
    var overlayOpacity: Double
    var coordinates: CLLocationCoordinate2D
    var cities: [City]
    var userActionAllowed: Bool
    var showWindParticles: Bool
    var lastRefresh: Date
    var oscarRadarState: OscarRadarState?
    var gfsImageState: GFSImageLayerState?

    private static let oscarRadarArrowHost = radarBaseURL

    private final class RainViewerRadarTileOverlay: MKTileOverlay {}
    private final class RainViewerInfraredTileOverlay: MKTileOverlay {}
    private final class LegacyDWDTileOverlay: WMSTileOverlay {}
    private final class OscarRadarArrowTileOverlay: MKTileOverlay {
        var frameID: String

        init(frameID: String) {
            self.frameID = frameID
            super.init(urlTemplate: nil)
            canReplaceMapContent = false
        }

        override func loadTile(
            at path: MKTileOverlayPath,
            result: @escaping (Data?, Error?) -> Void
        ) {
            guard let url = URL(
                string: "\(RadarMapView.oscarRadarArrowHost)/radar/vector-tiles/\(frameID)/\(path.z)/\(path.x)/\(path.y).webp"
            ) else {
                result(nil, nil)
                return
            }

            var request = URLRequest(url: url)
            request.addAPIContactIdentity()

            if let cached = URLCache.shared.cachedResponse(for: request), !cached.data.isEmpty {
                result(cached.data, nil)
                return
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let data, let response, !data.isEmpty {
                    URLCache.shared.storeCachedResponse(
                        CachedURLResponse(response: response, data: data),
                        for: request
                    )
                }
                result(data, error)
            }.resume()
        }
    }
    private final class SelectedCityAnnotation: NSObject, MKAnnotation {
        let coordinate: CLLocationCoordinate2D
        let title: String?
        let identity: String

        init(city: City) {
            self.coordinate = CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
            self.title = city.label
            self.identity = "\(city.label)|\(city.lat)|\(city.lon)"
        }
    }

    struct RainViewerOverlayTemplates {
        let radar: String?
        let infrared: String?
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RadarMapView
        var animatingRenderer: OscarRadarAnimatingRenderer?
        var lastRenderedFrameIndex: Int = -1
        var lastRenderedOscarFrameKey: String?
        var hasRenderedOscarFrame = false
        var gfsImageRenderer: OscarRadarAnimatingRenderer?
        var lastGFSImageFrameIndex: Int = -1
        var lastGFSImageFrameKey: String?
        var lastGFSImageLayer: WeatherTileLayer?
        var lastGFSBounds: OscarRadarBounds?
        var hasRenderedGFSFrame = false
        var rainViewerRadarOverlayID: String? = nil
        var rainViewerInfraredOverlayID: String? = nil
        var isLoadingRainViewerRadar = false
        var isLoadingRainViewerInfrared = false
        var rainViewerTemplatesTask: Task<RainViewerOverlayTemplates, Error>? = nil
        private var oscarArrowOverlay: OscarRadarArrowTileOverlay?
        var windParticleView: WindParticleView?
        var lastWindFrameKey: String?
        private var selectedCityAnnotation: SelectedCityAnnotation?

        init(_ parent: RadarMapView) {
            self.parent = parent
            super.init()
        }

        deinit {
            rainViewerTemplatesTask?.cancel()
        }

        func syncOscarArrowOverlay(frameKey: String, on mapView: MKMapView) {
            if let overlay = oscarArrowOverlay {
                if overlay.frameID != frameKey {
                    overlay.frameID = frameKey
                    (mapView.renderer(for: overlay) as? MKTileOverlayRenderer)?.reloadData()
                }
                if !mapView.overlays.contains(where: { ($0 as AnyObject) === overlay }) {
                    mapView.addOverlay(overlay, level: .aboveLabels)
                }
                return
            }

            let overlay = OscarRadarArrowTileOverlay(frameID: frameKey)
            oscarArrowOverlay = overlay
            mapView.addOverlay(overlay, level: .aboveLabels)
        }

        func removeOscarArrowOverlay(from mapView: MKMapView) {
            if let overlay = oscarArrowOverlay,
               mapView.overlays.contains(where: { ($0 as AnyObject) === overlay }) {
                mapView.removeOverlay(overlay)
            }
            oscarArrowOverlay = nil
        }

        @MainActor
        func rainViewerTemplates() async throws -> RainViewerOverlayTemplates {
            if let rainViewerTemplatesTask {
                return try await rainViewerTemplatesTask.value
            }

            let task = Task {
                let rainViewerData = try await APIClient().getRainViewerMaps()
                let host = rainViewerData.host ?? "https://tilecache.rainviewer.com"
                let radarTemplate = rainViewerData.radar?.past?.last.map {
                    "\(host)\($0.path ?? "")/256/{z}/{x}/{y}/4/1_1.png"
                }
                let infraredTemplate = rainViewerData.satellite?.infrared?.last.map {
                    "\(host)\($0.path ?? "")/256/{z}/{x}/{y}/0/0_0.png"
                }
                return RainViewerOverlayTemplates(radar: radarTemplate, infrared: infraredTemplate)
            }
            rainViewerTemplatesTask = task

            do {
                let result = try await task.value
                rainViewerTemplatesTask = nil
                return result
            } catch {
                rainViewerTemplatesTask = nil
                throw error
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let oscarOverlay = overlay as? OscarRadarImageOverlay {
                if let existing = animatingRenderer { return existing }
                let r = OscarRadarAnimatingRenderer(overlay: oscarOverlay)
                r.alpha = CGFloat(parent.overlayOpacity)
                // Feed images immediately so the overlay is visible without
                // waiting for the next frame-index change (fixes blank-on-first-load).
                if let state = parent.oscarRadarState, let frame = state.currentFrame {
                    r.updateImages(imageA: frame.cgImage, imageB: state.nextFrame?.cgImage)
                    lastRenderedFrameIndex = state.renderFrameIndex ?? state.currentFrameIndex
                    lastRenderedOscarFrameKey = frame.key
                    hasRenderedOscarFrame = true
                }
                animatingRenderer = r
                return r
            }
            if let gfsOverlay = overlay as? GFSFullWorldImageOverlay {
                if let existing = gfsImageRenderer { return existing }
                let r = OscarRadarAnimatingRenderer(gfsOverlay: gfsOverlay)
                r.alpha = CGFloat(parent.overlayOpacity)
                if let state = parent.gfsImageState {
                    r.updateImages(imageA: state.currentFrame, imageB: state.nextFrame)
                    lastGFSImageFrameIndex = state.renderFrameIndex ?? state.currentFrameIndex
                    lastGFSImageFrameKey = state.currentFrameKey
                    lastGFSImageLayer = state.currentLayer
                    hasRenderedGFSFrame = state.currentFrame != nil || state.nextFrame != nil
                }
                gfsImageRenderer = r
                return r
            }
            if overlay is OscarRadarArrowTileOverlay {
                let r = MKTileOverlayRenderer(overlay: overlay)
                r.alpha = 1.0
                return r
            }
            let r = MKTileOverlayRenderer(overlay: overlay)
            r.alpha = parent.overlayOpacity
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if annotation is SelectedCityAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "SelectedCityMarker")
                    as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "SelectedCityMarker")
                view.annotation = annotation
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: "location.fill")
                view.displayPriority = .required
                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            windParticleView?.onMapRegionChanged()
        }

        func syncSelectedCityAnnotation(on mapView: MKMapView) {
            let selectedCity = parent.cities.first(where: \.selected)

            guard let selectedCity else {
                if let existing = selectedCityAnnotation {
                    mapView.removeAnnotation(existing)
                    selectedCityAnnotation = nil
                }
                return
            }

            let identity = "\(selectedCity.label)|\(selectedCity.lat)|\(selectedCity.lon)"
            if selectedCityAnnotation?.identity == identity {
                return
            }

            if let existing = selectedCityAnnotation {
                mapView.removeAnnotation(existing)
            }

            let annotation = SelectedCityAnnotation(city: selectedCity)
            selectedCityAnnotation = annotation
            mapView.addAnnotation(annotation)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        let coordinateRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: coordinates.latitude, longitude: coordinates.longitude),
            latitudinalMeters: 130000, longitudinalMeters: 130000)
        mapView.setRegion(coordinateRegion, animated: false)

        // Add wind particle overlay above the map content.
        let particleView = WindParticleView(frame: mapView.bounds)
        particleView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        particleView.mapView = mapView
        mapView.addSubview(particleView)
        context.coordinator.windParticleView = particleView

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self  // keep parent reference current

        let oscarOverlays      = mapView.overlays.filter { $0 is OscarRadarImageOverlay }
        let oscarArrowOverlays = mapView.overlays.filter { $0 is OscarRadarArrowTileOverlay }
        let gfsImageOverlays   = mapView.overlays.filter { $0 is GFSFullWorldImageOverlay }
        let rainViewerRadarOverlays = mapView.overlays.filter { $0 is RainViewerRadarTileOverlay }
        let rainViewerInfraredOverlays = mapView.overlays.filter { $0 is RainViewerInfraredTileOverlay }
        let legacyDWDOverlays = mapView.overlays.filter { $0 is LegacyDWDTileOverlay }
        let otherOverlays      = mapView.overlays.filter {
            !($0 is OscarRadarImageOverlay)
                && !($0 is OscarRadarArrowTileOverlay)
                && !($0 is GFSFullWorldImageOverlay)
                && !($0 is RainViewerRadarTileOverlay)
                && !($0 is RainViewerInfraredTileOverlay)
                && !($0 is LegacyDWDTileOverlay)
        }

        mapView.delegate = context.coordinator
        context.coordinator.syncSelectedCityAnnotation(on: mapView)
        mapView.removeOverlays(otherOverlays)

        if let settings = settingsService.settings {
            let canShowRainViewer = settingsService.activeTileLayer == nil && !settingsService.oscarRadarLayer

            if settings.rainviewerLayer && canShowRainViewer {
                if rainViewerRadarOverlays.isEmpty && !context.coordinator.isLoadingRainViewerRadar {
                    context.coordinator.isLoadingRainViewerRadar = true
                    Task {
                        do {
                            let templates = try await context.coordinator.rainViewerTemplates()
                            if let urlTemplate = templates.radar {
                                DispatchQueue.main.async {
                                    context.coordinator.isLoadingRainViewerRadar = false
                                    guard context.coordinator.rainViewerRadarOverlayID != urlTemplate else { return }
                                    mapView.removeOverlays(mapView.overlays.filter { $0 is RainViewerRadarTileOverlay })
                                    context.coordinator.rainViewerRadarOverlayID = urlTemplate
                                    let overlay = RainViewerRadarTileOverlay(urlTemplate: urlTemplate)
                                    overlay.canReplaceMapContent = false
                                    mapView.addOverlay(overlay)
                                }
                            } else {
                                DispatchQueue.main.async {
                                    context.coordinator.isLoadingRainViewerRadar = false
                                }
                            }
                        } catch {
                            DispatchQueue.main.async {
                                context.coordinator.isLoadingRainViewerRadar = false
                            }
                            print("Error fetching RainViewer data: \(error)")
                        }
                    }
                }
            } else if !rainViewerRadarOverlays.isEmpty {
                mapView.removeOverlays(rainViewerRadarOverlays)
                context.coordinator.rainViewerRadarOverlayID = nil
            }

            if settings.dwdLayer && !settingsService.oscarRadarLayer {
                if legacyDWDOverlays.isEmpty {
                    let referenceSystem = WebMapServiceConstants.version == "1.1.1" ? "SRS" : "CRS"
                    let urlLayers = "layers=dwd:RADOLAN-RY&"
                    let urlVersion = "version=\(WebMapServiceConstants.version)&"
                    let urlReferenceSystem = "\(referenceSystem)=EPSG:\(WebMapServiceConstants.epsg)&"
                    let urlWidthAndHeight =
                        "width=\(WebMapServiceConstants.tileSize)&height=\(WebMapServiceConstants.tileSize)&"
                    let urlFormat = "format=\(WebMapServiceConstants.format)&format_options=MODE:refresh&"
                    let urlTransparent = "transparent=\(WebMapServiceConstants.transparent)&"
                    let useMercator = WebMapServiceConstants.epsg == "900913"
                    let urlString =
                        WebMapServiceConstants.baseUrl + "?styles=&service=WMS&request=GetMap&"
                        + urlLayers + urlVersion + urlReferenceSystem + urlWidthAndHeight
                        + urlFormat + urlTransparent
                    let overlay = LegacyDWDTileOverlay(
                        urlArg: urlString, useMercator: useMercator, wmsVersion: WebMapServiceConstants.version)
                    overlay.applyColorTransform = true
                    mapView.addOverlay(overlay)
                }
            } else if !legacyDWDOverlays.isEmpty {
                mapView.removeOverlays(legacyDWDOverlays)
            }

            if settings.infrarotLayer && canShowRainViewer {
                if rainViewerInfraredOverlays.isEmpty && !context.coordinator.isLoadingRainViewerInfrared {
                    context.coordinator.isLoadingRainViewerInfrared = true
                    Task {
                        do {
                            let templates = try await context.coordinator.rainViewerTemplates()
                            if let urlTemplate = templates.infrared {
                                DispatchQueue.main.async {
                                    context.coordinator.isLoadingRainViewerInfrared = false
                                    guard context.coordinator.rainViewerInfraredOverlayID != urlTemplate else { return }
                                    mapView.removeOverlays(mapView.overlays.filter { $0 is RainViewerInfraredTileOverlay })
                                    context.coordinator.rainViewerInfraredOverlayID = urlTemplate
                                    let overlay = RainViewerInfraredTileOverlay(urlTemplate: urlTemplate)
                                    overlay.canReplaceMapContent = false
                                    mapView.addOverlay(overlay)
                                }
                            } else {
                                DispatchQueue.main.async {
                                    context.coordinator.isLoadingRainViewerInfrared = false
                                }
                            }
                        } catch {
                            DispatchQueue.main.async {
                                context.coordinator.isLoadingRainViewerInfrared = false
                            }
                            print("Error fetching RainViewer data: \(error)")
                        }
                    }
                }
            } else if !rainViewerInfraredOverlays.isEmpty {
                mapView.removeOverlays(rainViewerInfraredOverlays)
                context.coordinator.rainViewerInfraredOverlayID = nil
            }

            // ── Oscar DWD radar (animated image overlay) ──────────────────
            if settingsService.oscarRadarLayer {
                if let oscarState = oscarRadarState,
                   let frame = oscarState.currentFrame,
                   let bounds = oscarState.bounds
                {
                    let renderedIndex = oscarState.renderFrameIndex ?? oscarState.currentFrameIndex
                    let frameKeyDidChange = context.coordinator.lastRenderedOscarFrameKey != frame.key

                    if context.coordinator.lastRenderedFrameIndex != renderedIndex
                        || frameKeyDidChange
                        || !context.coordinator.hasRenderedOscarFrame
                    {
                        context.coordinator.lastRenderedFrameIndex = renderedIndex
                        context.coordinator.lastRenderedOscarFrameKey = frame.key
                        context.coordinator.animatingRenderer?.updateImages(
                            imageA: frame.cgImage,
                            imageB: oscarState.nextFrame?.cgImage
                        )
                        context.coordinator.hasRenderedOscarFrame = true
                    }

                    if oscarOverlays.isEmpty {
                        let overlay = OscarRadarImageOverlay(bounds: bounds)
                        mapView.addOverlay(overlay, level: .aboveRoads)
                    }

                    if let r = context.coordinator.animatingRenderer {
                        r.stopAnimation()
                    }

                    context.coordinator.syncOscarArrowOverlay(frameKey: frame.key, on: mapView)
                }
            } else {
                mapView.removeOverlays(oscarOverlays)
                mapView.removeOverlays(oscarArrowOverlays)
                context.coordinator.removeOscarArrowOverlay(from: mapView)
                context.coordinator.animatingRenderer?.stopAnimation()
                context.coordinator.lastRenderedFrameIndex = -1
                context.coordinator.lastRenderedOscarFrameKey = nil
                context.coordinator.hasRenderedOscarFrame = false
            }

            // ── Full-world image overlay (ICON-D2 / GFS) ─────────────────
            if settingsService.activeTileLayer != nil,
               let gfsState = gfsImageState, let bounds = gfsState.bounds {
                let layerDidChange = context.coordinator.lastGFSImageLayer != gfsState.currentLayer
                let boundsDidChange = context.coordinator.lastGFSBounds != bounds
                let frameKeyDidChange = context.coordinator.lastGFSImageFrameKey != gfsState.currentFrameKey

                if layerDidChange || boundsDidChange {
                    if !gfsImageOverlays.isEmpty {
                        mapView.removeOverlays(gfsImageOverlays)
                    }
                    context.coordinator.gfsImageRenderer = nil
                    context.coordinator.lastGFSImageFrameIndex = -1
                    context.coordinator.lastGFSImageFrameKey = nil
                    context.coordinator.lastGFSImageLayer = gfsState.currentLayer
                    context.coordinator.lastGFSBounds = bounds
                    context.coordinator.hasRenderedGFSFrame = false
                }

                if gfsImageOverlays.isEmpty {
                    let overlay = GFSFullWorldImageOverlay(bounds: bounds)
                    mapView.addOverlay(overlay, level: .aboveRoads)
                }

                let hasRenderableFrame = gfsState.currentFrame != nil || gfsState.nextFrame != nil
                let renderedIndex = gfsState.renderFrameIndex ?? gfsState.currentFrameIndex
                if hasRenderableFrame &&
                    (
                        layerDidChange
                        || boundsDidChange
                        || frameKeyDidChange
                        || context.coordinator.lastGFSImageFrameIndex != renderedIndex
                        || !context.coordinator.hasRenderedGFSFrame
                    )
                {
                    context.coordinator.lastGFSImageFrameIndex = renderedIndex
                    context.coordinator.lastGFSImageFrameKey = gfsState.currentFrameKey
                    context.coordinator.lastGFSImageLayer = gfsState.currentLayer
                    context.coordinator.lastGFSBounds = bounds
                    context.coordinator.gfsImageRenderer?.updateImages(
                        imageA: gfsState.currentFrame, imageB: gfsState.nextFrame)
                    context.coordinator.hasRenderedGFSFrame = true
                }
            } else {
                if !gfsImageOverlays.isEmpty {
                    mapView.removeOverlays(gfsImageOverlays)
                    context.coordinator.gfsImageRenderer = nil
                }
                context.coordinator.lastGFSImageFrameIndex = -1
                context.coordinator.lastGFSImageFrameKey = nil
                context.coordinator.lastGFSImageLayer = nil
                context.coordinator.lastGFSBounds = nil
                context.coordinator.hasRenderedGFSFrame = false
            }

            // ── Wind particle layer ───────────────────────────────────────
            let isWindLayer = showWindParticles && (
                settingsService.activeTileLayer == .iconWind
                || settingsService.activeTileLayer == .gfsWind
            )
            if let particleView = context.coordinator.windParticleView {
                if isWindLayer,
                   let gfsState = gfsImageState,
                   let frameKey = gfsState.currentFrameKey,
                   let layer = settingsService.activeTileLayer
                {
                    particleView.activeLayer = layer

                    if context.coordinator.lastWindFrameKey != frameKey {
                        context.coordinator.lastWindFrameKey = frameKey
                        particleView.frameKey = frameKey

                        // Prefetch tiles for adjacent frames so scrubbing feels instant.
                        let index = gfsState.renderFrameIndex ?? gfsState.currentFrameIndex
                        let keys = gfsState.frameKeys
                        if index > 0 {
                            particleView.prefetchFrame(frameId: keys[index - 1], layer: layer)
                        }
                        if index + 1 < keys.count {
                            particleView.prefetchFrame(frameId: keys[index + 1], layer: layer)
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
                } else {
                    particleView.isHidden = true
                    particleView.stopDisplayLink()
                    if !isWindLayer {
                        particleView.frameKey = nil
                        particleView.activeLayer = nil
                        context.coordinator.lastWindFrameKey = nil
                    }
                }
            }
        }

        // Auto-update region for static (non-interactive) views
        if !userActionAllowed {
            let currentCenter = mapView.centerCoordinate
            let desiredCenter = coordinates
            let currentLoc = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)
            let desiredLoc = CLLocation(latitude: desiredCenter.latitude, longitude: desiredCenter.longitude)
            if currentLoc.distance(from: desiredLoc) > 1000 {
                DispatchQueue.main.async {
                    let region = MKCoordinateRegion(
                        center: desiredCenter, latitudinalMeters: 100000, longitudinalMeters: 100000)
                    mapView.setRegion(region, animated: false)
                }
            }
        }

        mapView.showsUserLocation = true
        if !userActionAllowed {
            mapView.isScrollEnabled = false
            mapView.isZoomEnabled = false
            mapView.isRotateEnabled = false
        }
    }
}
