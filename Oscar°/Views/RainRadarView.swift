import SwiftUI
import MapKit

struct RainRadarView: UIViewRepresentable {
    @Binding var timer: Timer?
    @Binding var overlay: MKTileOverlay?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Set map type and region
        uiView.mapType = .standard
        let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 51.3397, longitude: 12.3731), span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0))
        uiView.setRegion(region, animated: true)
        
        // Add rain radar overlay if not nil
        if let overlay = overlay {
            uiView.removeOverlays(uiView.overlays)
            uiView.addOverlay(overlay)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        
        var parent: RainRadarView
        
        init(_ parent: RainRadarView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            } else {
                return MKOverlayRenderer(overlay: overlay)
            }
            
        }
        
    }
}
