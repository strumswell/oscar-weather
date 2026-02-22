import MapKit
import UIKit

// ---------------------------------------------------------------------------
// MARK: - Oscar Radar (simple lat/lon bounding box)

class OscarRadarImageOverlay: NSObject, MKOverlay {
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init(bounds: OscarRadarBounds) {
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: bounds.north, longitude: bounds.west))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: bounds.south, longitude: bounds.east))
        let rect = MKMapRect(x: nw.x, y: nw.y, width: se.x - nw.x, height: se.y - nw.y)
        self.boundingMapRect = rect
        self.coordinate = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        super.init()
    }
}

class OscarRadarImageOverlayRenderer: MKOverlayRenderer {
    // Pre-decoded, pre-flipped CGImage — ready for direct context.draw() with no transform.
    private var cachedCGImage: CGImage?
    private let overlayRect: MKMapRect
    // Coalescing flag: multiple updateImage() calls within one run-loop turn
    // collapse into a single setNeedsDisplay() at the next opportunity.
    private var hasPendingRedraw = false

    init(overlay: OscarRadarImageOverlay, image: CGImage?) {
        self.cachedCGImage = image
        self.overlayRect = overlay.boundingMapRect
        super.init(overlay: overlay)
    }

    func updateImage(_ cgImage: CGImage?) {
        cachedCGImage = cgImage
        guard !hasPendingRedraw else { return }
        hasPendingRedraw = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasPendingRedraw = false
            self.setNeedsDisplay()
        }
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let cgImage = cachedCGImage else { return }
        // Image is pre-flipped at load time — direct draw, no transform needed.
        context.draw(cgImage, in: self.rect(for: overlayRect))
    }
}
