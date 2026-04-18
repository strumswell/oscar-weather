import MapKit
import UIKit
import Foundation

// ---------------------------------------------------------------------------
// MARK: - Oscar Radar overlay anchor

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

// ---------------------------------------------------------------------------
// MARK: - GFS full-world image overlay anchor

/// Distinct type from OscarRadarImageOverlay so the Coordinator can tell them apart.
final class GFSFullWorldImageOverlay: NSObject, MKOverlay {
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

// ---------------------------------------------------------------------------
// MARK: - Animating overlay renderer (zero sync lag, no tile seams)
//
// Design: double-buffered draw state.
//
//  • updateImages() / startAnimation() / stopAnimation() run on the MAIN thread.
//    They write to "pending" state (no lock needed — main thread only).
//
//  • tick() (CADisplayLink, main thread) is the ONLY place that commits
//    pending → draw state.  It then calls setNeedsDisplay() ONCE per frame.
//    Because all tiles redrawn in response to that single setNeedsDisplay()
//    call read the same draw state, no tile seams can appear.
//
//  • draw() runs on MKMapView's background render thread and only reads
//    draw state, which is protected by `drawLock`.

private final class DisplayLinkProxy: NSObject {
    weak var target: OscarRadarAnimatingRenderer?
    @objc func tick(_ link: CADisplayLink) { target?.tick(link) }
}

final class OscarRadarAnimatingRenderer: MKOverlayRenderer {

    // MARK: - Pending state  (main thread only — no lock)
    private var pendingImageA: CGImage?
    private var pendingImageB: CGImage?
    private var hasPendingUpdate = false
    private var isAnimating = false

    // MARK: - Draw state  (written on main thread in tick(), read on bg thread in draw())
    private let drawLock = NSLock()
    private var drawImageA: CGImage?
    private var drawImageB: CGImage?
    private var blendFactor: Float = 0

    private let overlayRect: MKMapRect
    private let frameDuration: CFTimeInterval = 0.5
    private var displayLink: CADisplayLink?

    var advanceFrameCallback: (() -> Void)?

    init(overlay: OscarRadarImageOverlay) {
        self.overlayRect = overlay.boundingMapRect
        super.init(overlay: overlay)
    }

    init(gfsOverlay: GFSFullWorldImageOverlay) {
        self.overlayRect = gfsOverlay.boundingMapRect
        super.init(overlay: gfsOverlay)
    }

    // MARK: - Public API (main thread)

    /// Queue a new frame pair.  The swap happens in the next tick() so all
    /// tiles are always drawn from the same snapshot — no visible seams.
    func updateImages(imageA: CGImage?, imageB: CGImage?) {
        pendingImageA = imageA
        pendingImageB = imageB
        hasPendingUpdate = true
        ensureDisplayLink()
    }

    func startAnimation() {
        isAnimating = true
        ensureDisplayLink()
    }

    func stopAnimation() {
        isAnimating = false
        drawLock.withLock { blendFactor = 0 }
        // Display link will stop itself on its next tick.
    }

    // MARK: - Display link lifecycle (main thread)

    private func ensureDisplayLink() {
        guard displayLink == nil else { return }
        let proxy = DisplayLinkProxy()
        proxy.target = self
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        if #available(iOS 15, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        } else {
            link.preferredFramesPerSecond = 60
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    // MARK: - Tick (main thread, called by CADisplayLink)

    @objc fileprivate func tick(_ link: CADisplayLink) {
        var needsDisplay = false
        var advance = false

        // 1. Atomically commit any pending image update to draw state.
        if hasPendingUpdate {
            drawLock.withLock {
                drawImageA = pendingImageA
                drawImageB = pendingImageB
                blendFactor = 0
            }
            pendingImageA = nil
            pendingImageB = nil
            hasPendingUpdate = false
            needsDisplay = true
        }

        // 2. Advance blend if animating.
        if isAnimating {
            drawLock.withLock {
                let dt = Float(link.targetTimestamp - link.timestamp)
                blendFactor += dt / Float(frameDuration)
                if blendFactor >= 1 {
                    blendFactor = 0
                    advance = true
                }
            }
            needsDisplay = true
        }

        // 3. Fire exactly one setNeedsDisplay() so all tiles use the same snapshot.
        if needsDisplay { setNeedsDisplay() }

        // 4. Advance frame (triggers updateImages() on next SwiftUI pass).
        if advance { advanceFrameCallback?() }

        // 5. Stop when there's nothing left to drive.
        if !isAnimating && !hasPendingUpdate {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    // MARK: - MKOverlayRenderer draw (MKMapView background thread)

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        drawLock.lock()
        let a     = drawImageA
        let b     = drawImageB
        let blend = CGFloat(blendFactor)
        drawLock.unlock()

        guard let a else { return }
        let drawRect = rect(for: overlayRect)

        if blend <= 0 || b == nil {
            context.draw(a, in: drawRect)
        } else {
            context.saveGState()
            context.setAlpha(1 - blend)
            context.draw(a, in: drawRect)
            context.setAlpha(blend)
            context.draw(b!, in: drawRect)
            context.restoreGState()
        }
    }

    deinit { displayLink?.invalidate() }
}

// ---------------------------------------------------------------------------
// MARK: - Weather Tile Overlay (ICON-D2 / GFS tile layers)

/// An MKTileOverlay that:
///   • serves from URLCache when pre-warmed (zero-flicker path)
///   • gracefully handles 204 No Content (tile outside data domain → transparent)
///   • manually stores fetched tiles so subsequent frames hit the cache
final class WeatherTileOverlay: MKTileOverlay {
    override func loadTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, Error?) -> Void
    ) {
        let url = self.url(forTilePath: path)
        var request = URLRequest(url: url)
        request.addAPIContactIdentity()

        // Fast path: already in cache
        if let cached = URLCache.shared.cachedResponse(for: request), !cached.data.isEmpty {
            result(cached.data, nil)
            return
        }

        // Fetch, cache, and return
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let http = response as? HTTPURLResponse, http.statusCode == 204 {
                // Outside domain — return empty data (transparent tile)
                result(Data(), nil)
                return
            }
            if let data, let response, !data.isEmpty {
                URLCache.shared.storeCachedResponse(
                    CachedURLResponse(response: response, data: data), for: request)
            }
            result(data, error)
        }.resume()
    }
}
