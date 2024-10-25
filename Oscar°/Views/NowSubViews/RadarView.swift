//
//  RadarView.swift
//  Weather
//
//  Created by Philipp Bolte on 11.08.21.
//

import SwiftUI
import MapKit

struct RadarView: View {
    @Environment(Location.self) private var location: Location
    @ObservedObject var settingsService: SettingService
    var showLayerSettings: Bool
    var locationService = LocationService.shared
    var userActionAllowed = true

    var body: some View {
        ZStack {
            RadarMapView(
                settingsService: settingsService,
                overlayOpacity: 0.7,
                coordinates: location.coordinates,
                cities: locationService.city.cities,
                userActionAllowed: userActionAllowed
            )
            if (showLayerSettings && settingsService.settings != nil) {
                VStack {
                    Spacer()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            if (settingsService.settings?.rainviewerLayer ?? false) {
                                LegendView(legendURL: "https://files.readme.io/6efe1f9-precipitation-si-spectrum.png")
                            }
                            if (settingsService.settings?.tempLayer ?? false) {
                                LegendView(legendURL: "https://files.readme.io/e19fcb3-temperature-si-spectrum.png")
                            }
                            if (settingsService.settings?.windDirectionLayer ?? false) {
                                LegendView(legendURL: "https://files.readme.io/bf5392a-wind-direction-spectrum.png")
                            }
                            if (settingsService.settings?.druckLayer ?? false) {
                                LegendView(legendURL: "https://files.readme.io/e8317b1-wind-speed-si-spectrum.png")
                            }
                            if (settingsService.settings?.humidityLayer ?? false) {
                                LegendView(legendURL: "https://files.readme.io/70de95d-humidity-spectrum.png")
                            }
                            if (settingsService.settings?.infrarotLayer ?? false) {
                                LegendView(legendURL: "https://files.readme.io/168dd28-cloud-cover-spectrum.png")
                            }
                        }
                    }
                }
            }
            if (showLayerSettings) {
                VStack {
                    HStack {
                        Spacer()
                        Menu {
                            Button(action: {
                                if (settingsService.settings != nil) {
                                    settingsService.settings!.rainviewerLayer.toggle()
                                    settingsService.save()
                                }
                            }) {
                                if (settingsService.settings?.rainviewerLayer ?? false) {
                                    Label(String(localized: "Regen (Global)"), systemImage: "checkmark")
                                } else {
                                    Text("Regen (Global)")
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
                                    Label(String(localized: "Windgeschwindidkeit"), systemImage: "checkmark")
                                } else {
                                    Text("Windgeschwindidkeit")
                                }
                            }
                            Button(action: {
                                if (settingsService.settings != nil) {
                                    settingsService.settings!.infrarotLayer.toggle()
                                    settingsService.save()
                                }
                            }) {
                                if (settingsService.settings?.infrarotLayer ?? false) {
                                    Label(String(localized: "Wolken"), systemImage: "checkmark")
                                } else {
                                    Text("Wolken")
                                }
                            }
                            Button(action: {
                                if (settingsService.settings != nil) {
                                    settingsService.settings!.humidityLayer.toggle()
                                    settingsService.save()
                                }
                            }) {
                                if (settingsService.settings?.humidityLayer ?? false) {
                                    Label(String(localized: "Luftfeuchtigkeit"), systemImage: "checkmark")
                                } else {
                                    Text("Luftfeuchtigkeit")
                                }
                            }
                            Button(action: {
                                if (settingsService.settings != nil) {
                                    settingsService.settings!.windDirectionLayer.toggle()
                                    settingsService.save()
                                }
                            }) {
                                if (settingsService.settings?.windDirectionLayer ?? false) {
                                    Label(String(localized: "Windrichtung"), systemImage: "checkmark")
                                } else {
                                    Text("Windrichtung")
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

struct LegendView: View {
    var legendURL: String
    var body: some View {
                AsyncImage(
                    url: URL(string: legendURL),
                    content: { image in
                        image
                            .resizable()
                            .cornerRadius(10)
                            .opacity(0.8)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 300, height: 200)
                    },
                    placeholder: {
                        VStack(alignment: .leading) {
                            Spacer()
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            Spacer()
                        }
                        .frame(height: 350)
                        .background(Color(UIColor.secondarySystemFill))
                    }
                )
                .padding(10)
            }
        
    }


extension RadarView {
    func getLayerLegendURL() -> String? {
        if (settingsService.settings!.rainviewerLayer) {
            return "https://files.readme.io/6efe1f9-precipitation-si-spectrum.png"
        }
        if (settingsService.settings!.tempLayer) {
            return "https://files.readme.io/e19fcb3-temperature-si-spectrum.png"
        }
        if (settingsService.settings!.windDirectionLayer) {
            return "https://files.readme.io/bf5392a-wind-direction-spectrum.png"
        }
        if (settingsService.settings!.druckLayer) {
            return "https://files.readme.io/e8317b1-wind-speed-si-spectrum.png"
        }
        if (settingsService.settings!.humidityLayer) {
            return "https://files.readme.io/e8317b1-wind-speed-si-spectrum.png"
        }
        if (settingsService.settings!.infrarotLayer) {
            return "https://files.readme.io/e8317b1-wind-speed-si-spectrum.png"
        }
        return nil
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
        let mapView = MKMapView()
        let coordinateRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: coordinates.latitude, longitude: coordinates.longitude), latitudinalMeters: 100000, longitudinalMeters: 100000)
        mapView.setRegion(coordinateRegion, animated: false)
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        let overlays = mapView.overlays
        
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
        
        if let settings = settingsService.settings {
            if settings.druckLayer {
                let overlay = MKTileOverlay(urlTemplate: "https://api.tomorrow.io/v4/map/tile/{z}/{x}/{y}/windSpeed/now.png?apikey=XjlExJsvt4ftR9UgSXvacuTwvwEEebiQ")
                mapView.addOverlay(overlay)
                //https://services.meteored.com/img/tiles/cep010/6/31/21/014_temp2m@2x.png
            }
            if settings.tempLayer {
                let overlay = MKTileOverlay(urlTemplate: "https://api.tomorrow.io/v4/map/tile/{z}/{x}/{y}/temperature/now.png?apikey=XjlExJsvt4ftR9UgSXvacuTwvwEEebiQ")
                mapView.addOverlay(overlay)
            }
            if settings.infrarotLayer {
                let overlay = MKTileOverlay(urlTemplate: "https://api.tomorrow.io/v4/map/tile/{z}/{x}/{y}/cloudCover/now.png?apikey=XjlExJsvt4ftR9UgSXvacuTwvwEEebiQ")
                mapView.addOverlay(overlay)
            }
            if settings.rainviewerLayer {
                let overlay = MKTileOverlay(urlTemplate: "https://api.tomorrow.io/v4/map/tile/{z}/{x}/{y}/precipitationIntensity/now.png?apikey=XjlExJsvt4ftR9UgSXvacuTwvwEEebiQ")
                mapView.addOverlay(overlay)
            }
            if settings.windDirectionLayer {
                let overlay = MKTileOverlay(urlTemplate: "https://api.tomorrow.io/v4/map/tile/{z}/{x}/{y}/windDirection/now.png?apikey=XjlExJsvt4ftR9UgSXvacuTwvwEEebiQ")
                mapView.addOverlay(overlay)
            }
            if settings.humidityLayer {
                let overlay = MKTileOverlay(urlTemplate: "https://api.tomorrow.io/v4/map/tile/{z}/{x}/{y}/humidity/now.png?apikey=XjlExJsvt4ftR9UgSXvacuTwvwEEebiQ")
                mapView.addOverlay(overlay)
            }
            if settings.dwdLayer {
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
        }
        
        // Let's auto-update the map region if users location changes for static views
        if !userActionAllowed {
            let currentCenter = mapView.centerCoordinate
            let desiredCenter = coordinates

            let currentLocation = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)
            let desiredLocation = CLLocation(latitude: desiredCenter.latitude, longitude: desiredCenter.longitude)
            let distance = currentLocation.distance(from: desiredLocation)

            if distance > 1000 {
                let coordinateRegion = MKCoordinateRegion(center: desiredCenter, latitudinalMeters: 100000, longitudinalMeters: 100000)
                mapView.setRegion(coordinateRegion, animated: false)
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


func getOverlay(host: String, path: String, color: String, options: String) -> MKTileOverlay {
    let template = "\(host)\(path)/256/{z}/{x}/{y}/\(color)/\(options).png"
    let overlay = MKTileOverlay(urlTemplate:template)
    return overlay
}
