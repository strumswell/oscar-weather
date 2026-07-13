import UIKit
import CoreLocation
import MapLibre

// MARK: - Display link proxy (breaks retain cycle)

private final class WindParticleDisplayLinkProxy: NSObject {
    weak var target: WindParticleView?
    @MainActor @objc func tick(_ link: CADisplayLink) { target?.tick(link) }
}

// MARK: - Wind particle overlay

/// A transparent UIView that renders animated wind particles above the map.
/// Placed as a sibling above the MLNMapView; the coordinator forwards region
/// changes so particles re-seed after pan/zoom.
/// Respects Reduce Motion: hidden when the system preference is enabled.
final class WindParticleView: UIView { 

    // MARK: - Configuration

    weak var mapView: MLNMapView?

    var frameKey: String? {
        didSet {
            guard frameKey != oldValue else { return }
            currentTileData = [:]
            fetchVisibleTilesTask?.cancel()
            if let key = frameKey, let layer = activeLayer {
                fetchVisibleTiles(frameId: key, layer: layer)
            }
        }
    }

    var activeLayer: WeatherTileLayer? {
        didSet {
            guard activeLayer != oldValue else { return }
            currentTileData = [:]
            fetchVisibleTilesTask?.cancel()
            if let key = frameKey, let layer = activeLayer {
                fetchVisibleTiles(frameId: key, layer: layer)
            }
        }
    }

    // MARK: - Particle model

    private struct Particle {
        var x: Float
        var y: Float
        var age: Int
        var ttl: Int
    }

    private var particles: [Particle] = []

    // MARK: - Wind tile data (main thread only)

    private var currentTileData: [String: WindFieldTile] = [:]
    private var fetchVisibleTilesTask: Task<Void, Never>?

    // MARK: - Rendering

    private let imageView = UIImageView()
    private var bitmapContext: CGContext?
    nonisolated(unsafe) private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    nonisolated(unsafe) private var reduceMotionObserver: NSObjectProtocol?
    nonisolated(unsafe) private var thermalObserver: NSObjectProtocol?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = false

        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)

        applyReduceMotionState()
        reduceMotionObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The observer is registered with `queue: .main`, so this fires on the main actor.
            MainActor.assumeIsolated { self?.applyReduceMotionState() }
        }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetParticles() }
        }
    }

    deinit {
        displayLink?.invalidate()
        fetchVisibleTilesTask?.cancel()
        if let obs = reduceMotionObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = thermalObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Reduce Motion

    private func applyReduceMotionState() {
        if UIAccessibility.isReduceMotionEnabled {
            isHidden = true
            stopDisplayLink()
        } else {
            isHidden = false
            startDisplayLinkIfNeeded()
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildBitmapContext()
        resetParticles()
    }

    private func rebuildBitmapContext() {
        // 2× is indistinguishable for soft trails and nearly halves the pixels the
        // fade + stroke + makeImage copy touch every tick (thermal, see the device
        // overheat history around parallel decode).
        let scale = min(2, window?.windowScene?.screen.scale ?? traitCollection.displayScale)
        let pw = bounds.width
        let ph = bounds.height
        guard pw > 0, ph > 0 else { return }
        let w = Int(pw * scale)
        let h = Int(ph * scale)

        guard let ctx = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return }

        // Flip to UIKit coordinate system (origin top-left, y increases downward).
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        bitmapContext = ctx
    }

    private func resetParticles() {
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return }
        let zoomLevel = approximateZoomLevel(for: mapView)
        let zoomDensityScale = particleDensityScale(for: zoomLevel)
        // Thermal backpressure: fewer particles once the device runs warm.
        let thermalScale: CGFloat
        switch ProcessInfo.processInfo.thermalState {
        case .critical: thermalScale = 0.25
        case .serious:  thermalScale = 0.5
        default:        thermalScale = 1
        }
        let count = min(900, max(130, Int((w * h / 1500) * CGFloat(zoomDensityScale) * thermalScale)))
        particles = (0..<count).map { _ in randomParticle(w: Float(w), h: Float(h)) }
    }

    private func randomParticle(w: Float, h: Float) -> Particle {
        // ~2.3–5.7 s at 30 fps: long enough for coherent streamlines, short
        // enough that the field re-seeds visibly after pan/zoom.
        return Particle(
            x: Float.random(in: 0..<w),
            y: Float.random(in: 0..<h),
            age: Int.random(in: 0..<40),
            ttl: Int.random(in: 70..<170)
        )
    }

    // MARK: - Display link

    func startDisplayLinkIfNeeded() {
        guard displayLink == nil, !UIAccessibility.isReduceMotionEnabled else { return }
        let proxy = WindParticleDisplayLinkProxy()
        proxy.target = self
        let link = CADisplayLink(target: proxy, selector: #selector(WindParticleDisplayLinkProxy.tick))
        if #available(iOS 15, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        } else {
            link.preferredFramesPerSecond = 30
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
    }

    // MARK: - Tick (CADisplayLink callback, main thread)

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let deltaMs = lastTimestamp == 0 ? 16.667 : min(40, (now - lastTimestamp) * 1000)
        lastTimestamp = now

        guard let ctx = bitmapContext, let mapView else { return }
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return }

        let zoomLevel = approximateZoomLevel(for: mapView)
        let usesGlobalModelStyle = activeLayer?.isGlobalModel == true
        let metersScale = particleVelocityScale(
            forContinuousZoom: continuousZoomLevel(for: mapView), usesGlobalModelStyle: usesGlobalModelStyle)
        let minPixelStep: Float = 0.2
        // Hard ceiling on the per-tick step — degenerate samples (tile seams,
        // spike values) must never paint screen-length streaks.
        let maxPixelStep: Float = 14
        let dt = max(0.5, deltaMs / 16.667)

        // Fade previous strokes instead of fully clearing, so particles leave trails.
        // 0.05/tick ≈ a ~0.7 s tail at 30 fps — the trail comes from persistence,
        // not from stretching the per-tick step. Far-out zooms get a slower fade:
        // continent-scale streamlines read better with longer tails.
        let frameRect = CGRect(origin: .zero, size: CGSize(width: w, height: h))
        ctx.setBlendMode(.destinationOut)
        ctx.setFillColor(UIColor.black.withAlphaComponent(zoomLevel <= 4 ? 0.035 : 0.05).cgColor)
        ctx.fill(frameRect)

        // Stroke style tuned for readability over busy radar/map imagery.
        ctx.setBlendMode(.normal)
        if usesGlobalModelStyle {
            ctx.setStrokeColor(red: 232/255, green: 244/255, blue: 1, alpha: 0.9)
        } else {
            ctx.setStrokeColor(red: 250/255, green: 252/255, blue: 1, alpha: 0.94)
        }
        ctx.setLineWidth(usesGlobalModelStyle ? 1.6 : 1.8)
        ctx.beginPath()

        let fw = Float(w)
        let fh = Float(h)
        // Axis-aligned fast path: per-particle conversions in plain Web-Mercator math
        // (two MapLibre `convert` calls per particle per tick would be the slow path).
        let visible = mapView.visibleCoordinateBounds
        let isAxisAligned = mapView.direction == 0 && mapView.camera.pitch == 0
        let nw = Self.mercatorUnit(latitude: visible.ne.latitude, longitude: visible.sw.longitude)
        let se = Self.mercatorUnit(latitude: visible.sw.latitude, longitude: visible.ne.longitude)
        let mercPerPixelX = (se.x - nw.x) / Double(w)
        let mercPerPixelY = (se.y - nw.y) / Double(h)

        for i in particles.indices {
            if particles[i].age >= particles[i].ttl {
                particles[i] = randomParticle(w: fw, h: fh)
                continue
            }

            let sx = particles[i].x
            let sy = particles[i].y
            let coord: CLLocationCoordinate2D
            if isAxisAligned, mercPerPixelX > 0, mercPerPixelY > 0 {
                coord = Self.coordinate(
                    mercX: nw.x + Double(sx) * mercPerPixelX,
                    mercY: nw.y + Double(sy) * mercPerPixelY
                )
            } else {
                coord = mapView.convert(
                    CGPoint(x: CGFloat(sx), y: CGFloat(sy)),
                    toCoordinateFrom: self
                )
            }

            guard let wind = sampleWind(at: coord) else {
                particles[i].age = particles[i].ttl
                continue
            }

            let cosLat = max(0.2, cos(coord.latitude * .pi / 180))
            let dLat = (wind.v * metersScale * dt) / 111_320
            let dLon = (wind.u * metersScale * dt) / (111_320 * cosLat)
            let newCoord = CLLocationCoordinate2D(
                latitude: coord.latitude + dLat,
                longitude: coord.longitude + dLon
            )
            let newPt: CGPoint
            if isAxisAligned, mercPerPixelX > 0, mercPerPixelY > 0 {
                let merc = Self.mercatorUnit(latitude: newCoord.latitude, longitude: newCoord.longitude)
                newPt = CGPoint(
                    x: (merc.x - nw.x) / mercPerPixelX,
                    y: (merc.y - nw.y) / mercPerPixelY
                )
            } else {
                newPt = mapView.convert(newCoord, toPointTo: self)
            }

            var dx = Float(newPt.x) - sx
            var dy = Float(newPt.y) - sy
            let spd = hypotf(dx, dy)
            if spd > 0 && spd < minPixelStep {
                let s = minPixelStep / spd
                dx *= s; dy *= s
            } else if spd > maxPixelStep {
                let s = maxPixelStep / spd
                dx *= s; dy *= s
            }

            let nx = sx + dx
            let ny = sy + dy

            // Cull particles that left the visible area
            if nx < -20 || ny < -20 || nx > fw + 20 || ny > fh + 20 {
                particles[i].age = particles[i].ttl
                continue
            }

            ctx.move(to: CGPoint(x: CGFloat(sx), y: CGFloat(sy)))
            ctx.addLine(to: CGPoint(x: CGFloat(nx), y: CGFloat(ny)))

            particles[i].x = nx
            particles[i].y = ny
            particles[i].age += 1
        }

        ctx.strokePath()

        if let cgImage = ctx.makeImage() {
            imageView.image = UIImage(cgImage: cgImage)
        }
    }

    // MARK: - Wind sampling (bilinear interpolation)

    private func sampleWind(at coord: CLLocationCoordinate2D) -> (u: Double, v: Double)? {
        for tile in currentTileData.values {
            let b = tile.bounds
            guard coord.latitude >= b.south, coord.latitude <= b.north,
                  coord.longitude >= b.west, coord.longitude <= b.east else { continue }
            let tx = (coord.longitude - b.west) / max(1e-6, b.east - b.west)
            let ty = (b.north - coord.latitude) / max(1e-6, b.north - b.south)
            if let result = bilinear(tile: tile, tx: tx, ty: ty) { return result }
        }
        return nil
    }

    private func bilinear(tile: WindFieldTile, tx: Double, ty: Double) -> (u: Double, v: Double)? {
        let gw = tile.gridWidth
        let gh = tile.gridHeight
        let fx = max(0, min(1, tx)) * Double(gw - 1)
        let fy = max(0, min(1, ty)) * Double(gh - 1)
        let x0 = Int(fx), y0 = Int(fy)
        let x1 = min(gw - 1, x0 + 1)
        let y1 = min(gh - 1, y0 + 1)
        let sx = fx - Double(x0)
        let sy = fy - Double(y0)

        let i00 = y0 * gw + x0, i10 = y0 * gw + x1
        let i01 = y1 * gw + x0, i11 = y1 * gw + x1

        guard let u00 = tile.u[i00], let u10 = tile.u[i10],
              let u01 = tile.u[i01], let u11 = tile.u[i11],
              let v00 = tile.v[i00], let v10 = tile.v[i10],
              let v01 = tile.v[i01], let v11 = tile.v[i11] else { return nil }

        let w00 = (1 - sx) * (1 - sy), w10 = sx * (1 - sy)
        let w01 = (1 - sx) * sy,       w11 = sx * sy
        return (
            u: u00 * w00 + u10 * w10 + u01 * w01 + u11 * w11,
            v: v00 * w00 + v10 * w10 + v01 * w01 + v11 * w11
        )
    }

    // MARK: - Tile management

    /// Called by the map coordinator when the region changes.
    func onMapRegionChanged() {
        guard let key = frameKey, let layer = activeLayer else { return }
        fetchVisibleTiles(frameId: key, layer: layer)
        resetParticles()
    }

    /// Kick off a prefetch for an adjacent frame (fire-and-forget).
    func prefetchFrame(frameId: String, layer: WeatherTileLayer) {
        guard let mapView else { return }
        let (z, positions) = visibleTilePositions(in: mapView)
        Task { await WindFieldCache.shared.prefetch(frameId: frameId, z: z, positions: positions, layer: layer) }
    }

    private func fetchVisibleTiles(frameId: String, layer: WeatherTileLayer) {
        fetchVisibleTilesTask?.cancel()
        guard let mapView else { return }
        let (z, positions) = visibleTilePositions(in: mapView)

        fetchVisibleTilesTask = Task {
            var nextTileData: [String: WindFieldTile] = [:]
            await withTaskGroup(of: (String, WindFieldTile?).self) { group in
                for (x, y) in positions {
                    let cacheKey = WindTileKey(
                        model: layer.windFieldPrefix, frameId: frameId, z: z, x: x, y: y)
                    let tileKey = "\(z)/\(x)/\(y)"
                    group.addTask {
                        let tile = await WindFieldCache.shared.tile(key: cacheKey, layer: layer)
                        return (tileKey, tile)
                    }
                }
                for await (tileKey, tile) in group {
                    guard !Task.isCancelled, let tile else { continue }
                    nextTileData[tileKey] = tile
                }
            }
            guard !Task.isCancelled else { return }
            currentTileData = nextTileData
        }
    }

    private func visibleTilePositions(in mapView: MLNMapView) -> (z: Int, positions: [(x: Int, y: Int)]) {
        let visible = mapView.visibleCoordinateBounds
        let z = approximateZoomLevel(for: mapView)
        let tilesPerSide = 1 << z

        let nw = Self.mercatorUnit(latitude: visible.ne.latitude, longitude: visible.sw.longitude)
        let se = Self.mercatorUnit(latitude: visible.sw.latitude, longitude: visible.ne.longitude)
        let minX = max(0, Int(nw.x * Double(tilesPerSide)))
        let maxX = min(tilesPerSide - 1, Int(se.x * Double(tilesPerSide)))
        let minY = max(0, Int(nw.y * Double(tilesPerSide)))
        let maxY = min(tilesPerSide - 1, Int(se.y * Double(tilesPerSide)))

        guard minX <= maxX, minY <= maxY else { return (z, []) }

        var positions: [(x: Int, y: Int)] = []
        for tx in minX...maxX {
            for ty in minY...maxY {
                positions.append((x: tx, y: ty))
            }
        }
        return (z, positions)
    }

    private func approximateZoomLevel(for mapView: MLNMapView) -> Int {
        let visible = mapView.visibleCoordinateBounds
        let lonSpan = visible.ne.longitude - visible.sw.longitude
        return max(0, min(8, Int(log2(360.0 / max(0.001, lonSpan)).rounded()) + 1))
    }

    private func approximateZoomLevel(for mapView: MLNMapView?) -> Int {
        guard let mapView else { return 5 }
        return approximateZoomLevel(for: mapView)
    }

    // MARK: - Web-Mercator helpers (normalized [0,1]², y grows south)

    private static func mercatorUnit(latitude: Double, longitude: Double) -> (x: Double, y: Double) {
        let lat = min(WebMercator.maxLatitude, max(-WebMercator.maxLatitude, latitude))
        return (WebMercator.unitX(longitude: longitude), WebMercator.unitY(latitude: lat))
    }

    private static func coordinate(mercX: Double, mercY: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: WebMercator.latitude(fromUnitY: mercY),
            longitude: WebMercator.longitude(fromUnitX: mercX)
        )
    }

    private func particleDensityScale(for zoomLevel: Int) -> Float {
        switch zoomLevel {
        case 0...2:
            return 1.6
        case 3...4:
            return 1.25
        case 5...6:
            return 1.0
        default:
            return 0.85
        }
    }

    /// Continuous, UNCAPPED zoom for the velocity scale. approximateZoomLevel's
    /// cap at 8 (the wind-tile zoom ceiling) must not leak in here: past the cap
    /// the 2^z compensation stopped tracking the map scale, so the per-tick pixel
    /// step doubled with every further zoom level — the "endless very long
    /// particles" deep-zoom bug.
    private func continuousZoomLevel(for mapView: MLNMapView) -> Double {
        let visible = mapView.visibleCoordinateBounds
        let lonSpan = visible.ne.longitude - visible.sw.longitude
        return max(0, log2(360.0 / max(0.001, lonSpan)) + 1)
    }

    /// Degrees-per-(m/s) factor chosen so a given wind speed moves a particle the
    /// SAME number of screen pixels at every zoom (the 2^z term cancels the map
    /// scale): 10 m/s ≈ 50 px/s. Far-out zooms are damped a touch — continental
    /// views read better when the field drifts rather than races.
    private func particleVelocityScale(
        forContinuousZoom zoom: Double, usesGlobalModelStyle: Bool
    ) -> Double {
        let scaleInvariant = 65.0 * pow(2, 6 - zoom)
        // Far-out boost: at continent scale the same px/s reads as stubby dashes,
        // so let the field flow faster (Windy-style long streamlines).
        let farOutBoost: Double
        switch zoom {
        case ...3.5: farOutBoost = 1.7
        case ...4.5: farOutBoost = 1.3
        default:     farOutBoost = 1.0
        }
        return scaleInvariant * farOutBoost * (usesGlobalModelStyle ? 1.1 : 1.0)
    }
}
