//
//  RadarView.swift
//  Weather
//
//  Created by Philipp Bolte on 11.08.21.
//

import SwiftUI
import MapKit

struct RadarView: View {
    @ObservedObject var settingsService: SettingService
    @Binding var radarMetadata: WeatherMapsResponse?
    var showLayerSettings: Bool
    var locationService = LocationService.shared
    var userActionAllowed = true

    var body: some View {
        ZStack {
            RadarMapView(
                overlay: getOverlay(host: radarMetadata?.host ?? "", path: radarMetadata?.radar.past[radarMetadata!.radar.past.count-1].path ?? "", color: "2", options: "1_1"),
                overlayOpacity: 0.7,
                cloudOverlay: getOverlay(host: radarMetadata?.host ?? "", path: radarMetadata?.satellite.infrared.last?.path ?? "", color: "0", options: "0_0"),
                coordinates: locationService.getCoordinates(),
                cities: locationService.city.cities,
                settings: settingsService.settings,
                userActionAllowed: userActionAllowed
            )
            if (showLayerSettings) {
                VStack {
                    HStack {
                        Spacer()
                        Menu {
                            Button(action: {
                                if (settingsService.settings != nil) {
                                    settingsService.settings!.infrarotLayer.toggle()
                                    settingsService.save()
                                }
                            }) {
                                if (settingsService.settings?.infrarotLayer ?? false) {
                                    Label(String(localized: "Infrarot"), systemImage: "checkmark")
                                } else {
                                    Text("Infrarot")
                                }
                            }
                            Button(action: {
                                if (settingsService.settings != nil) {
                                    settingsService.settings!.rainviewerLayer.toggle()
                                    settingsService.save()
                                }
                            }) {
                                if (settingsService.settings?.rainviewerLayer ?? false) {
                                    Label(String(localized: "Regen (Rainviewer)"), systemImage: "checkmark")
                                } else {
                                    Text("Regen (Rainviewer)")
                                }
                            }
                            Button(action: {
                                if (settingsService.settings != nil) {
                                    settingsService.settings!.dwdLayer.toggle()
                                    settingsService.save()
                                }
                            }) {
                                if (settingsService.settings?.dwdLayer ?? false) {
                                    Label(String(localized: "Regen (DWD)"), systemImage: "checkmark")
                                } else {
                                    Text("Regen (DWD)")
                                }
                            }
                            Button(action: {
                                if (settingsService.settings != nil) {
                                    settingsService.settings!.tempLayer.toggle()
                                    settingsService.save()
                                }
                            }) {
                                if (settingsService.settings?.tempLayer ?? false) {
                                    Label(String(localized: "Temperatur"), systemImage: "checkmark")
                                } else {
                                    Text("Temperatur")
                                }
                            }
                            Button(action: {
                                if (settingsService.settings != nil) {
                                    settingsService.settings!.druckLayer.toggle()
                                    settingsService.save()
                                }
                            }) {
                                if (settingsService.settings?.druckLayer ?? false) {
                                    Label(String(localized: "Wind & Druck"), systemImage: "checkmark")
                                } else {
                                    Text("Wind & Druck")
                                }
                            }
                        } label: {
                            Image(systemName: "map.fill")
                                .resizable()
                                .frame(width: 25, height: 25)
                                .foregroundColor(.gray.opacity(0.9))
                        }
                        .frame(width: 40, height: 40)
                        .background(Color(.systemGray6).opacity(0.8))
                        .cornerRadius(5)
                    }
                    Spacer()
                }
                .padding(.trailing)
                .padding(.top)
            }
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
    var overlay: MKTileOverlay
    var overlayOpacity: Double
    var cloudOverlay: MKTileOverlay
    var coordinates: CLLocationCoordinate2D
    var cities: [City]
    var settings: Settings?
    var userActionAllowed: Bool
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RadarMapView

        init(_ parent: RadarMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKTileOverlayRenderer(overlay: overlay)
            renderer.alpha = parent.overlayOpacity
            return renderer
        }
    }
        

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        return MKMapView()
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        let overlays = mapView.overlays
        let hour = Calendar.current.component(.hour, from: Date())
        
        
        mapView.removeAnnotations(mapView.annotations)

        for city in self.cities {
            if (city.selected) {
                let selectedCity = MKPointAnnotation()
                selectedCity.title = city.label
                selectedCity.coordinate = CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
                mapView.addAnnotation(selectedCity)
                break;
            }
        }


        mapView.delegate = context.coordinator
        //mapView.overrideUserInterfaceStyle = .dark
        mapView.removeOverlays(overlays)
                
        if (settings?.druckLayer ?? false) {
            let overlay = MKTileOverlay(urlTemplate: "https://services.meteored.com/img/tiles/cep010/{z}/{x}/{y}/0\(String(format: "%02d",hour-2))_prsvie.png")
            mapView.addOverlay(overlay)
            //https://services.meteored.com/img/tiles/cep010/6/31/21/014_temp2m@2x.png
        }
        if (settings?.tempLayer ?? false) {
            let overlay = MKTileOverlay(urlTemplate: "https://services.meteored.com/img/tiles/cep010/{z}/{x}/{y}/0\(String(format: "%02d",hour-2))_temp2m.png")
            mapView.addOverlay(overlay)
        }
        if (settings?.infrarotLayer ?? false) {
            mapView.addOverlay(cloudOverlay)
        }
        if (settings?.rainviewerLayer ?? false) {
            mapView.addOverlay(overlay)
        }
        if (settings?.dwdLayer ?? true) {
            var referenceSystem = ""
            if WebMapServiceConstants.version == "1.1.1" {
                referenceSystem = "SRS"
            } else {
                referenceSystem = "CRS"
            }

            let urlLayers = "layers=dwd:Niederschlagsradar&"
            let urlVersion = "version=\(WebMapServiceConstants.version)&"
            let urlReferenceSystem = "\(referenceSystem)=EPSG:\(WebMapServiceConstants.epsg)&"
            let urlWidthAndHeight = "width=\(WebMapServiceConstants.tileSize)&height=\(WebMapServiceConstants.tileSize)&"
            let urlFormat = "format=\(WebMapServiceConstants.format)&format_options=MODE:refresh&"
            let urlTransparent = "transparent=\(WebMapServiceConstants.transparent)&"

            var useMercator = false
            if(WebMapServiceConstants.epsg == "900913"){
                useMercator = true
            }

            let urlString = WebMapServiceConstants.baseUrl + "?styles=&service=WMS&request=GetMap&" + urlLayers + urlVersion + urlReferenceSystem + urlWidthAndHeight + urlFormat + urlTransparent //+ "&time=" + time[index]
            let overlay = WMSTileOverlay(urlArg: urlString, useMercator: useMercator, wmsVersion: WebMapServiceConstants.version)
            mapView.addOverlay(overlay)
        }
        
        // Define region to center map on -> Modify lat so selected city is visible in the map view (Map view extends down behind the weather sheet -> pull to refresh shows no blank space behind sheet
        let coordinateRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: coordinates.latitude, longitude: coordinates.longitude), latitudinalMeters: 100000, longitudinalMeters: 100000)
        
        mapView.setRegion(coordinateRegion, animated: false)
        mapView.mapType = .standard
        mapView.showsUserLocation = true
        if !userActionAllowed {
            mapView.isScrollEnabled = false
            mapView.isZoomEnabled = false
            mapView.isRotateEnabled = false
        }
    }
}


func getOverlay(host: String, path: String, color: String, options: String) -> MKTileOverlay {
    let template = "\(host)\(path)/256/{z}/{x}/{y}/\(color)/\(options).png"
    let overlay = MKTileOverlay(urlTemplate:template)
    return overlay
}
