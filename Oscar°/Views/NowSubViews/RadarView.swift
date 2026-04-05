//
//  RadarView.swift
//  Weather
//
//  Created by Philipp Bolte on 11.08.21.
//

import MapKit
import SwiftUI

struct RadarView: View {
    @Environment(Location.self) private var location: Location
    @ObservedObject var settingsService: SettingService
    @State private var lastRefresh = Date()
    var showLayerSettings: Bool
    var locationService = LocationService.shared
    var userActionAllowed = true
    var oscarRadarState: OscarRadarState?
    var weatherTileState: WeatherTileState?

    var body: some View {
        ZStack {
            RadarMapView(
                settingsService: settingsService,
                overlayOpacity: 0.7,
                coordinates: location.coordinates,
                cities: locationService.city.cities,
                userActionAllowed: userActionAllowed,
                lastRefresh: lastRefresh,
                oscarRadarState: oscarRadarState,
                weatherTileState: weatherTileState
            )

            // Timestamp badge + optional colormap legend — top-left
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        if settingsService.oscarRadarLayer, let frame = oscarRadarState?.currentFrame {
                            RadarTimestampBadge(
                                timestamp: frame.timestamp,
                                isLive: oscarRadarState?.isCurrentFrameLive ?? false
                            )
                            if showLayerSettings {
                                ColormapVerticalLegend(colormap: .radar)
                            }
                        } else if settingsService.activeTileLayer != nil,
                                  let ts = weatherTileState?.currentFrameTimestamp {
                            let _ = weatherTileState?.currentFrameIndex
                            RadarTimestampBadge(timestamp: ts, isLive: false)
                            if showLayerSettings, let cm = settingsService.activeTileLayer?.colormap {
                                ColormapVerticalLegend(colormap: cm)
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
        weatherTileState?.pause()
    }

    private func activateRainviewer() {
        settingsService.oscarRadarLayer = false
        settingsService.activeTileLayer = nil
        settingsService.settings?.rainviewerLayer = true
        settingsService.settings?.dwdLayer = false
        settingsService.save()
        oscarRadarState?.pause()
        weatherTileState?.pause()
    }

    private func activateDWDRadar() {
        settingsService.activeTileLayer = nil
        settingsService.settings?.rainviewerLayer = false
        settingsService.save()
        settingsService.oscarRadarLayer = true
        weatherTileState?.pause()
    }

    private func activateTileLayer(_ layer: WeatherTileLayer) {
        settingsService.oscarRadarLayer = false
        settingsService.settings?.rainviewerLayer = false
        settingsService.save()
        oscarRadarState?.pause()
        settingsService.activeTileLayer = layer
        // Parent's onChange(of: settingsService.activeTileLayer) will call switchLayer
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
    var lastRefresh: Date
    var oscarRadarState: OscarRadarState?
    var weatherTileState: WeatherTileState?

    private static let oscarRadarArrowHost = "https://radar.oscars.love"
    private static func arrowTileTemplate(frameId: String) -> String {
        "\(oscarRadarArrowHost)/radar/vector-tiles/\(frameId)/{z}/{x}/{y}.webp"
    }

    private final class OscarRadarArrowTileOverlay: MKTileOverlay {}

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RadarMapView
        var animatingRenderer: OscarRadarAnimatingRenderer?
        var lastRenderedFrameIndex: Int = -1
        /// Combines tilePath + frameKey — detects both frame advances and layer switches.
        var lastTileOverlayID: String? = nil

        init(_ parent: RadarMapView) {
            self.parent = parent
            super.init()
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let oscarOverlay = overlay as? OscarRadarImageOverlay {
                if let existing = animatingRenderer { return existing }
                let r = OscarRadarAnimatingRenderer(overlay: oscarOverlay)
                r.alpha = CGFloat(parent.overlayOpacity)
                r.advanceFrameCallback = { [weak self] in
                    Task { @MainActor in
                        self?.parent.oscarRadarState?.advanceFrame()
                    }
                }
                // Feed images immediately so the overlay is visible without
                // waiting for the next frame-index change (fixes blank-on-first-load).
                if let state = parent.oscarRadarState, let frame = state.currentFrame {
                    let next = (state.currentFrameIndex + 1) % max(1, state.frames.count)
                    r.updateImages(imageA: frame.cgImage, imageB: state.frames[next]?.cgImage)
                    lastRenderedFrameIndex = state.currentFrameIndex
                }
                animatingRenderer = r
                return r
            }
            if let tileOverlay = overlay as? WeatherTileOverlay {
                let r = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                r.alpha = CGFloat(parent.overlayOpacity)
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
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self  // keep parent reference current

        let oscarOverlays      = mapView.overlays.filter { $0 is OscarRadarImageOverlay }
        let oscarArrowOverlays = mapView.overlays.filter { $0 is OscarRadarArrowTileOverlay }
        let tileOverlays       = mapView.overlays.filter { $0 is WeatherTileOverlay }
        let otherOverlays      = mapView.overlays.filter {
            !($0 is OscarRadarImageOverlay)
                && !($0 is OscarRadarArrowTileOverlay)
                && !($0 is WeatherTileOverlay)
        }

        mapView.removeAnnotations(mapView.annotations)

        for city in self.cities {
            if city.selected {
                let pin = MKPointAnnotation()
                pin.title = city.label
                pin.coordinate = CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
                mapView.addAnnotation(pin)
                break
            }
        }

        mapView.delegate = context.coordinator
        mapView.removeOverlays(otherOverlays)

        if let settings = settingsService.settings {
            if settings.rainviewerLayer {
                Task {
                    do {
                        let rainViewerData = try await APIClient().getRainViewerMaps()
                        if let mostRecentFrame = rainViewerData.radar?.past?.last {
                            let host = rainViewerData.host ?? "https://tilecache.rainviewer.com"
                            let path = mostRecentFrame.path ?? ""
                            let urlTemplate = "\(host)\(path)/256/{z}/{x}/{y}/4/1_1.png"
                            DispatchQueue.main.async {
                                let overlay = MKTileOverlay(urlTemplate: urlTemplate)
                                overlay.canReplaceMapContent = false
                                mapView.addOverlay(overlay)
                            }
                        }
                    } catch {
                        print("Error fetching RainViewer data: \(error)")
                    }
                }
            }

            if settings.dwdLayer {
                var referenceSystem = ""
                if WebMapServiceConstants.version == "1.1.1" {
                    referenceSystem = "SRS"
                } else {
                    referenceSystem = "CRS"
                }
                let urlLayers = "layers=dwd:RADOLAN-RY&"
                let urlVersion = "version=\(WebMapServiceConstants.version)&"
                let urlReferenceSystem = "\(referenceSystem)=EPSG:\(WebMapServiceConstants.epsg)&"
                let urlWidthAndHeight =
                    "width=\(WebMapServiceConstants.tileSize)&height=\(WebMapServiceConstants.tileSize)&"
                let urlFormat = "format=\(WebMapServiceConstants.format)&format_options=MODE:refresh&"
                let urlTransparent = "transparent=\(WebMapServiceConstants.transparent)&"
                var useMercator = WebMapServiceConstants.epsg == "900913"
                let urlString =
                    WebMapServiceConstants.baseUrl + "?styles=&service=WMS&request=GetMap&"
                    + urlLayers + urlVersion + urlReferenceSystem + urlWidthAndHeight
                    + urlFormat + urlTransparent
                let overlay = WMSTileOverlay(
                    urlArg: urlString, useMercator: useMercator, wmsVersion: WebMapServiceConstants.version)
                overlay.applyColorTransform = true
                mapView.addOverlay(overlay)
            }

            if settings.infrarotLayer {
                Task {
                    do {
                        let rainViewerData = try await APIClient().getRainViewerMaps()
                        if let mostRecentFrame = rainViewerData.satellite?.infrared?.last {
                            let host = rainViewerData.host ?? "https://tilecache.rainviewer.com"
                            let path = mostRecentFrame.path ?? ""
                            let urlTemplate = "\(host)\(path)/256/{z}/{x}/{y}/0/0_0.png"
                            DispatchQueue.main.async {
                                let overlay = MKTileOverlay(urlTemplate: urlTemplate)
                                overlay.canReplaceMapContent = false
                                mapView.addOverlay(overlay)
                            }
                        }
                    } catch {
                        print("Error fetching RainViewer data: \(error)")
                    }
                }
            }

            // ── Oscar DWD radar (animated image overlay) ──────────────────
            if settingsService.oscarRadarLayer {
                if let oscarState = oscarRadarState,
                   let frame = oscarState.currentFrame,
                   let bounds = oscarState.bounds
                {
                    let nextIndex = (oscarState.currentFrameIndex + 1) % max(1, oscarState.frames.count)

                    if context.coordinator.lastRenderedFrameIndex != oscarState.currentFrameIndex {
                        context.coordinator.lastRenderedFrameIndex = oscarState.currentFrameIndex
                        context.coordinator.animatingRenderer?.updateImages(
                            imageA: frame.cgImage,
                            imageB: oscarState.frames[nextIndex]?.cgImage
                        )
                    }

                    if oscarOverlays.isEmpty {
                        let overlay = OscarRadarImageOverlay(bounds: bounds)
                        mapView.addOverlay(overlay, level: .aboveRoads)
                    }

                    if let r = context.coordinator.animatingRenderer {
                        if oscarState.isPlaying {
                            oscarState.cancelInternalTimer()
                            r.startAnimation()
                        } else {
                            r.stopAnimation()
                        }
                    }

                    mapView.removeOverlays(oscarArrowOverlays)
                    let arrowOverlay = OscarRadarArrowTileOverlay(
                        urlTemplate: Self.arrowTileTemplate(frameId: frame.key))
                    arrowOverlay.canReplaceMapContent = false
                    mapView.addOverlay(arrowOverlay, level: .aboveLabels)
                }
            } else {
                mapView.removeOverlays(oscarOverlays)
                mapView.removeOverlays(oscarArrowOverlays)
                context.coordinator.animatingRenderer?.stopAnimation()
            }

            // ── Tile-based weather layers (ICON-D2 / GFS) ─────────────────
            if let tileState = weatherTileState,
               let activeLayer = settingsService.activeTileLayer,
               let frameKey = tileState.currentFrameKey
            {
                // Use activeLayer (from settings) as the source of truth for the path.
                // tileState.currentLayer lags behind by one async hop after a layer switch,
                // so reading it here would produce the wrong URL template.
                let overlayID = "\(activeLayer.tilePath)/\(frameKey)"
                if overlayID != context.coordinator.lastTileOverlayID {
                    context.coordinator.lastTileOverlayID = overlayID
                    mapView.removeOverlays(tileOverlays)
                    let template = "\(WeatherTileState.baseURL)/\(activeLayer.tilePath)/\(frameKey)/{z}/{x}/{y}.webp"
                    let overlay = WeatherTileOverlay(urlTemplate: template)
                    overlay.canReplaceMapContent = false
                    overlay.tileSize = CGSize(width: 256, height: 256)
                    mapView.addOverlay(overlay, level: .aboveRoads)
                }
            } else if !tileOverlays.isEmpty {
                mapView.removeOverlays(tileOverlays)
                context.coordinator.lastTileOverlayID = nil
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
