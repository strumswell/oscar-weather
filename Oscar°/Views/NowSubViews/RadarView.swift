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
    
    var body: some View {
        ZStack {
            RadarMapView(
                settingsService: settingsService,
                overlayOpacity: 0.7,
                coordinates: location.coordinates,
                cities: locationService.city.cities,
                userActionAllowed: userActionAllowed,
                lastRefresh: lastRefresh,
                oscarRadarState: oscarRadarState
            )
            // Timestamp badge — top-left, visible in both NowView and MapDetailView
            if settingsService.oscarRadarLayer, let frame = oscarRadarState?.currentFrame {
                VStack {
                    HStack {
                        RadarTimestampBadge(
                            timestamp: frame.timestamp,
                            isLive: oscarRadarState?.isCurrentFrameLive ?? false
                        )
                        .padding(12)
                        Spacer()
                    }
                    Spacer()
                }
            }

            if showLayerSettings {
                VStack {
                    HStack {
                        Spacer()
                        Menu {
                            Button(action: {
                                settingsService.oscarRadarLayer.toggle()
                            }) {
                                if settingsService.oscarRadarLayer {
                                    Label(String(localized: "Radar (DWD)"), systemImage: "checkmark")
                                } else {
                                    Text("Radar (DWD)")
                                }
                            }
                            Button(action: {
                                if settingsService.settings != nil {
                                    settingsService.settings!.rainviewerLayer.toggle()
                                    settingsService.save()
                                }
                            }) {
                                if settingsService.settings?.rainviewerLayer ?? false {
                                    Label(String(localized: "Regen (Global)"), systemImage: "checkmark")
                                } else {
                                    Text("Regen (Global)")
                                }
                            }
                            Button(action: {
                                if settingsService.settings != nil {
                                    settingsService.settings!.dwdLayer.toggle()
                                    settingsService.save()
                                }
                            }) {
                                if settingsService.settings?.dwdLayer ?? false {
                                    Label(String(localized: "Regen (DWD)"), systemImage: "checkmark")
                                } else {
                                    Text("Regen (DWD)")
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
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RadarMapView
        
        init(_ parent: RadarMapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let oscarOverlay = overlay as? OscarRadarImageOverlay {
                let renderer = OscarRadarImageOverlayRenderer(
                    overlay: oscarOverlay,
                    image: parent.oscarRadarState?.currentFrame?.cgImage)
                renderer.alpha = parent.overlayOpacity
                return renderer
            }
            let renderer = MKTileOverlayRenderer(overlay: overlay)
            renderer.alpha = parent.overlayOpacity
            return renderer
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
        // Capture Oscar overlay before the bulk remove so we can update it in-place.
        let oscarOverlays = mapView.overlays.filter { $0 is OscarRadarImageOverlay }
        let otherOverlays = mapView.overlays.filter { !($0 is OscarRadarImageOverlay) }
        
        mapView.removeAnnotations(mapView.annotations)
        
        for city in self.cities {
            if city.selected {
                let selectedCity = MKPointAnnotation()
                selectedCity.title = city.label
                selectedCity.coordinate = CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
                mapView.addAnnotation(selectedCity)
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
                
                var useMercator = false
                if WebMapServiceConstants.epsg == "900913" {
                    useMercator = true
                }
                
                let urlString =
                WebMapServiceConstants.baseUrl + "?styles=&service=WMS&request=GetMap&" + urlLayers
                + urlVersion + urlReferenceSystem + urlWidthAndHeight + urlFormat + urlTransparent
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
            
            if settingsService.oscarRadarLayer {
                if let oscarState = oscarRadarState,
                   let frame = oscarState.currentFrame,
                   let bounds = oscarState.bounds
                {
                    if let existing = oscarOverlays.first as? OscarRadarImageOverlay,
                       let renderer = mapView.renderer(for: existing) as? OscarRadarImageOverlayRenderer
                    {
                        renderer.updateImage(frame.cgImage)
                    } else {
                        mapView.removeOverlays(oscarOverlays)
                        let overlay = OscarRadarImageOverlay(bounds: bounds)
                        mapView.addOverlay(overlay, level: .aboveRoads)
                    }
                }
            } else {
                mapView.removeOverlays(oscarOverlays)
            }
        }
        
        // Let's auto-update the map region if users location changes for static views
        if !userActionAllowed {
            let currentCenter = mapView.centerCoordinate
            let desiredCenter = coordinates
            
            let currentLocation = CLLocation(
                latitude: currentCenter.latitude, longitude: currentCenter.longitude)
            let desiredLocation = CLLocation(
                latitude: desiredCenter.latitude, longitude: desiredCenter.longitude)
            let distance = currentLocation.distance(from: desiredLocation)
            
            if distance > 1000 {
                DispatchQueue.main.async {
                    let coordinateRegion = MKCoordinateRegion(
                        center: desiredCenter, latitudinalMeters: 100000, longitudinalMeters: 100000)
                    mapView.setRegion(coordinateRegion, animated: false)
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
