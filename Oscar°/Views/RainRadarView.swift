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

struct ContentView2 : View {
    
    @State private var timer : Timer?
    @State private var overlay : MKTileOverlay?
    @State private var pos = 0
    @State private var time: String?
    @Binding var radarMetadata: WeatherMapsResponse?
    
    var body : some View {
        
        VStack{
            RainRadarView(timer: $timer, overlay: $overlay)
            Text(time ?? "")
            
            Button(action:{
                if self.timer == nil{
                    self.timer = Timer.scheduledTimer(withTimeInterval : 1 ,repeats:true){_ in
                    
                        let path = radarMetadata?.radar.past[pos].path
                        self.time = Date(timeIntervalSince1970: TimeInterval(radarMetadata?.radar.past[pos].time ?? 0)).formatted()
                        
                        // Create rain radar tile overlay with date parameter
                        let template = "https://tilecache.rainviewer.com\(path ?? "")/256/{z}/{x}/{y}/2/1_0.png"
                        let overlay = MKTileOverlay(urlTemplate : template)
                        
                        // Remove previous overlay if any and add new one
                        self.overlay = overlay

                        if (pos == (radarMetadata?.radar.past.count ?? 0 )-1) {
                            pos = 0
                        } else {
                            pos += 1
                        }
                    }
                }else{
                    self.timer?.invalidate()
                    self.timer=nil
                    
                }
            }){
                Text(self.timer == nil ? "Play" : "Stop")
                    .font(.largeTitle)
                
            }
            
        }
        
    }
    
}
