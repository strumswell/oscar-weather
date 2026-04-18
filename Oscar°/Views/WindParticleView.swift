import UIKit
import MapKit

// MARK: - Display link proxy (breaks retain cycle)

private final class WindParticleDisplayLinkProxy: NSObject {
    weak var target: WindParticleView?
    @objc func tick(_ link: CADisplayLink) { target?.tick(link) }
}

// MARK: - Wind particle overlay

/// A transparent UIView that renders animated wind particles above the map.
/// Placed as a subview of MKMapView so it tracks pan/zoom automatically.
/// Respects Reduce Motion: hidden when the system preference is enabled.
final class WindParticleView: UIView {

    // MARK: - Configuration

    weak var mapView: MKMapView?

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
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var reduceMotionObserver: NSObjectProtocol?

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
            self?.applyReduceMotionState()
        }
    }

    deinit {
        displayLink?.invalidate()
        fetchVisibleTilesTask?.cancel()
        if let obs = reduceMotionObserver {
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
        let scale = window?.windowScene?.screen.scale ?? traitCollection.displayScale
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
        let count = max(60, Int((w * h / 5200) * CGFloat(zoomDensityScale)))
        particles = (0..<count).map { _ in randomParticle(w: Float(w), h: Float(h)) }
    }

    private func randomParticle(w: Float, h: Float) -> Particle {
        return Particle(
            x: Float.random(in: 0..<w),
            y: Float.random(in: 0..<h),
            age: Int.random(in: 0..<24),
            ttl: Int.random(in: 12..<30)
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
        let isGFS = activeLayer == .gfsWind
        let metersScale = particleVelocityScale(for: zoomLevel, isGFS: isGFS)
        let minPixelStep: Float = isGFS ? 0.22 : 0.18
        let trailLengthScale = particleTrailScale(for: zoomLevel, isGFS: isGFS)
        let dt = max(0.5, deltaMs / 16.667)

        // Fade previous strokes instead of fully clearing, so particles leave trails.
        let frameRect = CGRect(origin: .zero, size: CGSize(width: w, height: h))
        ctx.setBlendMode(.destinationOut)
        ctx.setFillColor(UIColor.black.withAlphaComponent(isGFS ? 0.12 : 0.1).cgColor)
        ctx.fill(frameRect)

        // Stroke style tuned for readability over busy radar/map imagery.
        ctx.setBlendMode(.normal)
        if isGFS {
            ctx.setStrokeColor(red: 232/255, green: 244/255, blue: 1, alpha: 0.92)
        } else {
            ctx.setStrokeColor(red: 250/255, green: 252/255, blue: 1, alpha: 0.96)
        }
        ctx.setLineWidth(isGFS ? 1.9 : 2.1)
        ctx.beginPath()

        let fw = Float(w)
        let fh = Float(h)

        for i in particles.indices {
            if particles[i].age >= particles[i].ttl {
                particles[i] = randomParticle(w: fw, h: fh)
                continue
            }

            let sx = particles[i].x
            let sy = particles[i].y
            let coord = mapView.convert(
                CGPoint(x: CGFloat(sx), y: CGFloat(sy)),
                toCoordinateFrom: self
            )

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
            let newPt = mapView.convert(newCoord, toPointTo: self)

            var dx = Float(newPt.x) - sx
            var dy = Float(newPt.y) - sy
            let spd = hypotf(dx, dy)
            if spd > 0 && spd < minPixelStep {
                let s = minPixelStep / spd
                dx *= s; dy *= s
            }

            dx *= trailLengthScale
            dy *= trailLengthScale

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
                    let cacheKey = WindTileKey(frameId: frameId, z: z, x: x, y: y)
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

    private func visibleTilePositions(in mapView: MKMapView) -> (z: Int, positions: [(x: Int, y: Int)]) {
        let lonSpan = mapView.region.span.longitudeDelta
        let z = max(0, min(8, Int(log2(360.0 / max(0.001, lonSpan)).rounded()) + 1))
        let tilesPerSide = 1 << z
        let worldSize = MKMapSize.world.width
        let rect = mapView.visibleMapRect

        let minX = max(0, Int(rect.minX / worldSize * Double(tilesPerSide)))
        let maxX = min(tilesPerSide - 1, Int(rect.maxX / worldSize * Double(tilesPerSide)))
        let minY = max(0, Int(rect.minY / worldSize * Double(tilesPerSide)))
        let maxY = min(tilesPerSide - 1, Int(rect.maxY / worldSize * Double(tilesPerSide)))

        guard minX <= maxX, minY <= maxY else { return (z, []) }

        var positions: [(x: Int, y: Int)] = []
        for tx in minX...maxX {
            for ty in minY...maxY {
                positions.append((x: tx, y: ty))
            }
        }
        return (z, positions)
    }

    private func approximateZoomLevel(for mapView: MKMapView) -> Int {
        let lonSpan = mapView.region.span.longitudeDelta
        return max(0, min(8, Int(log2(360.0 / max(0.001, lonSpan)).rounded()) + 1))
    }

    private func approximateZoomLevel(for mapView: MKMapView?) -> Int {
        guard let mapView else { return 5 }
        return approximateZoomLevel(for: mapView)
    }

    private func particleDensityScale(for zoomLevel: Int) -> Float {
        switch zoomLevel {
        case 0...2:
            return 2.5
        case 3...4:
            return 1.7
        case 5...6:
            return 0.75
        default:
            return 0.4
        }
    }

    private func particleTrailScale(for zoomLevel: Int, isGFS: Bool) -> Float {
        let base: Float = isGFS ? 1.8 : 1.6
        switch zoomLevel {
        case 0...2:
            return base * 9
        case 3...4:
            return base * 7
        case 5...6:
            return base * 2.95
        default:
            return base * 0.65
        }
    }

    private func particleVelocityScale(for zoomLevel: Int, isGFS: Bool) -> Double {
        let base: Double = isGFS ? 160 : 130
        switch zoomLevel {
        case 0...2:
            return base * 0.01
        case 3...4:
            return base * 0.3
        case 5...6:
            return base * 0.78
        default:
            return base
        }
    }
}
