//
//  RadarView.swift
//  Weather
//
//  Created by Philipp Bolte on 11.08.21.
//

import SwiftUI
import MapKit

struct RadarView: View {
    //@Binding var location: CLLocationCoordinate2D?
    @ObservedObject var now: NowViewModel
    @Binding var radarMetadata: WeatherMapsResponse?

    var body: some View {
        Text("Radar")
            .font(.system(size: 20))
            .bold()
            .foregroundColor(.white.opacity(0.8))
            .shadow(color: .white, radius: 40)
            .padding([.leading, .top, .bottom])
        
        RadarMapView(overlay: getOverlay(host: radarMetadata?.host ?? "", path: radarMetadata?.radar.past[radarMetadata!.radar.past.count-1].path ?? ""), coordinates: now.getActiveLocation())
            .frame(height: 300, alignment: .center)
            .background(Color.black.opacity(0.2))
            .cornerRadius(10)
            .font(.system(size: 18))
            .padding([.leading, .trailing])
            .padding(.bottom, 30)
    }
}

struct RadarMapView: UIViewRepresentable {
    var overlay: MKTileOverlay
    var coordinates: CLLocationCoordinate2D

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RadarMapView

        init(_ parent: RadarMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKTileOverlayRenderer(overlay: overlay)
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

        mapView.delegate = context.coordinator
        mapView.overrideUserInterfaceStyle = .dark
        mapView.removeOverlays(overlays)
        mapView.addOverlay(overlay)
        
        let coordinateRegion = MKCoordinateRegion(center: coordinates, latitudinalMeters: 100000, longitudinalMeters: 100000)
        mapView.setRegion(coordinateRegion, animated: false)
        mapView.showsUserLocation = true
    }
}


func getOverlay(host: String, path: String) -> MKTileOverlay {
    let template = "\(host)\(path)/256/{z}/{x}/{y}/8/1_1.png"
    let overlay = MKTileOverlay(urlTemplate:template)
    return overlay
}
