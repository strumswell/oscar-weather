//
//  RadarSnapshotRenderer.swift
//  Oscar°WidgetExtension
//
//  CPU compositor for the radar widget. iOS denies GPU work to widget extensions
//  on device ("Insufficient Permission to submit GPU work from background"), so
//  MapLibre cannot render here — the APP prerenders the fiord basemap with
//  MLNMapSnapshotter (WidgetBasemapRenderer) into the app group, and this type
//  overlays live data with CoreGraphics only:
//
//    cached basemap PNG (+ its exact rendered coordinate rectangle)
//      + oscar-server raster tiles of the frame closest to now
//      + the app's motion arrows (from /motion JSON, precip-gated)
//      + location marker
//
//  Layer pick per location: DWD → EUMETNET OPERA → NOAA MRMS radar by coverage,
//  else the global GFS precip forecast. Everything is fetched before compositing,
//  so the widget image is never half-loaded. Memory stays tiny (a handful of
//  256 px tiles; the big value grids never enter this process — ImageIO peaks
//  >100 MB on the OPERA lossless WebP, measured, vs the ~30 MB widget budget).
//

import CoreLocation
import Foundation
import UIKit

@MainActor
enum RadarSnapshotRenderer {
    struct Rendered {
        let image: UIImage
        let frameDate: Date?
    }

    /// Same framing as WidgetBasemapRenderer and the previous MapKit widget.
    private static let mapSpanMeters = 65_000.0
    /// Matches the prerendered basemap PNGs.
    private static let compositeScale: CGFloat = 2
    private static let radarOverlayAlpha: CGFloat = 0.7
    /// Fallback canvas when no basemap has been prerendered yet (app not opened
    /// since install / location change) — the fiord style's land tone.
    private static let fallbackBackground = UIColor(red: 0.20, green: 0.22, blue: 0.28, alpha: 1)

    // MARK: - Entry point

    /// Composites the widget map for a location. Returns nil only when there is
    /// neither a cached basemap nor any precip data (e.g. offline on first run) —
    /// the provider then shows its connectivity fallback.
    static func render(center: CLLocationCoordinate2D, size: CGSize) async -> Rendered? {
        let plan: RadarOverlayPlan
        if let region = RadarRegion.bestSource(latitude: center.latitude, longitude: center.longitude) {
            plan = await radarPlan(region: region, around: center)
        } else {
            plan = await gfsPlan()
        }

        let basemap = loadBasemap(center: center, size: size)
        guard basemap != nil || plan.tileURLTemplate != nil else { return nil }

        let bounds = basemap?.bounds ?? fittedBounds(around: center, spanMeters: mapSpanMeters, size: size)
        let frame = MercatorFrame(bounds: bounds, size: size)
        let tiles = await fetchOverlayTiles(plan: plan, frame: frame)

        let format = UIGraphicsImageRendererFormat()
        format.scale = compositeScale
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            if let basemap {
                basemap.image.draw(in: CGRect(origin: .zero, size: size))
            } else {
                fallbackBackground.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            for tile in tiles {
                tile.image.draw(in: tile.rect, blendMode: .normal, alpha: radarOverlayAlpha)
            }
            drawArrows(plan.arrows, frame: frame, context: context.cgContext)
            drawLocationMarker(at: frame.point(for: center))
        }
        return Rendered(image: image, frameDate: plan.frameDate)
    }

    // MARK: - Basemap

    private static func loadBasemap(
        center: CLLocationCoordinate2D, size: CGSize
    ) -> (image: UIImage, bounds: GeoBox)? {
        guard let (record, image) = WidgetBasemapStore.load(size: size) else { return nil }
        let bounds = GeoBox(south: record.south, west: record.west, north: record.north, east: record.east)
        // A basemap rendered for a different location is still geographically exact
        // (overlays project through its stored bounds) — but once the marker would
        // leave the frame, treat it as missing and let the app re-render.
        guard bounds.contains(center) else { return nil }
        return (image, bounds)
    }

    // MARK: - Overlay plans

    /// Radar coverage: raster tiles of the frame closest to now, plus the motion
    /// arrows of that frame (best-effort).
    private static func radarPlan(region: RadarRegion, around center: CLLocationCoordinate2D) async -> RadarOverlayPlan {
        guard let url = URL(string: "\(radarBaseURL)/radar/\(region.pathComponent)/frames"),
              let data = await fetchData(url, freshest: true),
              let response = try? JSONDecoder().decode(RadarFramesResponse.self, from: data),
              let frame = closestFrame(in: response.frames.map { ($0.key, $0.timestamp) })
        else { return RadarOverlayPlan() }

        var plan = RadarOverlayPlan(
            tileURLTemplate: "\(radarBaseURL)/radar/\(region.pathComponent)/frames/\(frame.key)/tiles/{z}/{x}/{y}",
            maximumTileZoom: 10,
            frameDate: frame.date
        )

        if let bounds = (response.imageBounds ?? response.bounds)?.asDomain,
           let motionURL = URL(string: "\(radarBaseURL)/radar/\(region.pathComponent)/motion"),
           let motionData = await fetchData(motionURL),
           let motion = RadarMotionData(jsonData: motionData),
           let pair = motion.pairsByFrom[frame.key] {
            let gate = await PrecipGate.load(
                around: center, spanMeters: mapSpanMeters * 1.8,
                region: region, frameKey: frame.key
            )
            plan.arrows = arrowFeatures(
                motion: motion, fieldIndex: pair.fieldIndex, bounds: bounds,
                cull: boundingBox(around: center, spanMeters: mapSpanMeters * 1.8),
                gate: gate
            )
        }
        return plan
    }

    /// Global fallback outside all radar coverages: GFS precipitation forecast,
    /// frame closest to now. No motion fields — no arrows.
    private static func gfsPlan() async -> RadarOverlayPlan {
        guard let url = URL(string: "\(radarBaseURL)/models/gfs/frames"),
              let data = await fetchData(url, freshest: true),
              let response = try? JSONDecoder().decode(ModelFramesResponse.self, from: data),
              let frame = closestFrame(in: response.frames.map { ($0.key, $0.validTime) })
        else { return RadarOverlayPlan() }

        return RadarOverlayPlan(
            tileURLTemplate: "\(radarBaseURL)/models/gfs/frames/\(frame.key)/precipitation/tiles/{z}/{x}/{y}",
            maximumTileZoom: 7,
            frameDate: frame.date
        )
    }

    nonisolated private static func closestFrame(in frames: [(key: String, timestamp: String)]) -> (key: String, date: Date)? {
        let now = Date()
        return frames
            .compactMap { frame in parsedDate(from: frame.timestamp).map { (frame.key, $0) } }
            .min { abs(now.timeIntervalSince($0.1)) < abs(now.timeIntervalSince($1.1)) }
    }

    // MARK: - Overlay tiles

    private struct OverlayTile {
        let rect: CGRect
        let image: UIImage
    }

    /// Fetches the raster tiles covering the frame at a zoom where tile pixels
    /// roughly match composite pixels (capped per source, like the app's layers).
    private static func fetchOverlayTiles(plan: RadarOverlayPlan, frame: MercatorFrame) async -> [OverlayTile] {
        guard let template = plan.tileURLTemplate else { return [] }
        let worldWidth = frame.x1 - frame.x0
        guard worldWidth > 0 else { return [] }
        let pixelWidth = Double(frame.size.width) * Double(compositeScale)
        let idealZoom = Int(floor(log2(pixelWidth / 256 / worldWidth)))
        let zoom = max(0, min(Int(plan.maximumTileZoom), idealZoom))
        let n = pow(2, Double(zoom))

        let x0 = Int(floor(frame.x0 * n)), x1 = Int(floor(frame.x1 * n))
        let y0 = Int(floor(frame.y0 * n)), y1 = Int(floor(frame.y1 * n))
        guard x0 >= 0, y0 >= 0, (x1 - x0 + 1) * (y1 - y0 + 1) <= 16 else { return [] }

        var tiles: [OverlayTile] = []
        for tx in x0...x1 {
            for ty in y0...y1 {
                let urlString = template
                    .replacingOccurrences(of: "{z}", with: "\(zoom)")
                    .replacingOccurrences(of: "{x}", with: "\(tx)")
                    .replacingOccurrences(of: "{y}", with: "\(ty)")
                guard let url = URL(string: urlString),
                      let data = await fetchData(url),
                      let image = UIImage(data: data) else { continue }
                let origin = frame.point(forWorldX: Double(tx) / n, worldY: Double(ty) / n)
                let corner = frame.point(forWorldX: Double(tx + 1) / n, worldY: Double(ty + 1) / n)
                tiles.append(OverlayTile(
                    rect: CGRect(x: origin.x, y: origin.y, width: corner.x - origin.x, height: corner.y - origin.y),
                    image: image
                ))
            }
        }
        return tiles
    }

    // MARK: - Drawing

    private static func drawArrows(_ arrows: [RadarArrow], frame: MercatorFrame, context: CGContext) {
        guard !arrows.isEmpty else { return }
        let icon = arrowImage()
        let visible = CGRect(origin: .zero, size: frame.size).insetBy(dx: -12, dy: -12)
        for arrow in arrows {
            let point = frame.point(for: arrow.coordinate)
            guard visible.contains(point) else { continue }
            context.saveGState()
            context.translateBy(x: point.x, y: point.y)
            context.rotate(by: arrow.rotation * .pi / 180)
            context.scaleBy(x: arrow.scale, y: arrow.scale)
            icon.draw(
                in: CGRect(x: -icon.size.width / 2, y: -icon.size.height / 2,
                           width: icon.size.width, height: icon.size.height),
                blendMode: .normal, alpha: 0.9
            )
            context.restoreGState()
        }
    }

    /// Thin north-pointing line arrow, black with a thin white border — identical
    /// to the app's paused-radar arrows.
    nonisolated private static func arrowImage() -> UIImage {
        let size = CGSize(width: 13, height: 18)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 6.5, y: 16.5))        // tail
        path.addLine(to: CGPoint(x: 6.5, y: 2))        // tip
        path.move(to: CGPoint(x: 3.8, y: 5.6))         // head left
        path.addLine(to: CGPoint(x: 6.5, y: 2))
        path.addLine(to: CGPoint(x: 9.2, y: 5.6))      // head right
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setStroke()
            path.lineWidth = 2.6
            path.stroke()
            UIColor.black.setStroke()
            path.lineWidth = 1.1
            path.stroke()
        }
    }

    /// Blue location dot, matching the previous MapKit widget's marker.
    private static func drawLocationMarker(at point: CGPoint) {
        let rect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
        UIColor.systemBlue.setFill()
        UIBezierPath(ovalIn: rect).fill()
        let outline = UIBezierPath(ovalIn: rect)
        UIColor.white.withAlphaComponent(0.8).setStroke()
        outline.lineWidth = 2
        outline.stroke()
    }

    // MARK: - Motion arrows (port of WeatherMapView's arrowFeatures)

    /// One arrow per coarse motion cell that carries precipitation and non-trivial
    /// flow, culled to the widget's viewport. Identical placement math to the app;
    /// only the precip gate differs (raster-tile alpha instead of the value grid).
    private static func arrowFeatures(
        motion: RadarMotionData, fieldIndex: Int, bounds: OscarRadarBounds,
        cull: GeoBox, gate: PrecipGate?
    ) -> [RadarArrow] {
        guard let gate, motion.fields.indices.contains(fieldIndex) else { return [] }
        let field = motion.fields[fieldIndex]
        let cols = motion.cols, rows = motion.rows
        guard field.count == cols * rows * 2 else { return [] }

        let yNorth = mercatorY(bounds.north)
        let ySouth = mercatorY(bounds.south)

        func coordinate(uvX: Double, uvY: Double) -> CLLocationCoordinate2D {
            let y = yNorth + uvY * (ySouth - yNorth)
            return CLLocationCoordinate2D(
                latitude: latitudeFromMercatorY(y),
                longitude: bounds.west + uvX * (bounds.east - bounds.west)
            )
        }

        var arrows: [RadarArrow] = []
        for row in 0..<rows {
            for col in 0..<cols {
                // Checkerboard: half the cells, evenly spread — matches the app.
                guard (row + col) % 2 == 0 else { continue }
                let u = Double(field[row * cols + col])
                let v = Double(field[cols * rows + row * cols + col])
                let speed = (u * u + v * v).squareRoot()
                guard speed >= 0.8 else { continue }

                let uvX = (Double(col) + 0.5) / Double(cols)
                let uvY = (Double(row) + 0.5) / Double(rows)
                let center = coordinate(uvX: uvX, uvY: uvY)
                guard cull.contains(center) else { continue }

                // ≥2 of 25 subsampled points inside the cell footprint carry precip —
                // the app's cellHasPrecip rule, sampled from the gate tiles.
                var hits = 0
                subsample: for sy in 0..<5 {
                    for sx in 0..<5 {
                        let x = uvX + (Double(sx) / 4 - 0.5) / Double(cols)
                        let y = uvY + (Double(sy) / 4 - 0.5) / Double(rows)
                        guard x >= 0, x <= 1, y >= 0, y <= 1 else { continue }
                        if gate.hasPrecip(at: coordinate(uvX: x, uvY: y)) {
                            hits += 1
                            if hits >= 2 { break subsample }
                        }
                    }
                }
                guard hits >= 2 else { continue }

                arrows.append(RadarArrow(
                    coordinate: center,
                    // +u = east, +v = south → clockwise-from-north degrees.
                    rotation: atan2(u, -v) * 180 / .pi,
                    // Slightly larger arrows for faster motion (0.6…1.15).
                    scale: 0.6 + min(speed / 4, 1) * 0.55
                ))
                if arrows.count >= 80 { return arrows }
            }
        }
        return arrows
    }

    // MARK: - Precip gate (alpha-sampled radar tiles)

    /// A few 256 px radar tiles around the viewport, kept as alpha planes; answers
    /// "is there precipitation at this coordinate" for the arrow gate. Bounded by
    /// construction: at most 6 tiles ≈ 400 KB transient.
    private struct PrecipGate {
        let zoom: Int
        let tiles: [Int: [UInt8]] // key: x << 16 | y, value: 256×256 alpha plane

        static let gateZoom = 8

        static func load(
            around center: CLLocationCoordinate2D, spanMeters: Double,
            region: RadarRegion, frameKey: String
        ) async -> PrecipGate? {
            let box = boundingBox(around: center, spanMeters: spanMeters)
            let x0 = tileX(box.west, zoom: gateZoom), x1 = tileX(box.east, zoom: gateZoom)
            let y0 = tileY(box.north, zoom: gateZoom), y1 = tileY(box.south, zoom: gateZoom)
            guard (x1 - x0 + 1) * (y1 - y0 + 1) <= 6 else { return nil }

            var tiles: [Int: [UInt8]] = [:]
            for x in x0...x1 {
                for y in y0...y1 {
                    guard let url = URL(string:
                        "\(radarBaseURL)/radar/\(region.pathComponent)/frames/\(frameKey)/tiles/\(gateZoom)/\(x)/\(y)"
                    ), let data = await fetchData(url), let alpha = alphaPlane(from: data) else { continue }
                    tiles[x << 16 | y] = alpha
                }
            }
            return tiles.isEmpty ? nil : PrecipGate(zoom: gateZoom, tiles: tiles)
        }

        func hasPrecip(at coordinate: CLLocationCoordinate2D) -> Bool {
            let scale = pow(2, Double(zoom)) * 256
            let worldX = (coordinate.longitude + 180) / 360 * scale
            let rad = coordinate.latitude * .pi / 180
            let worldY = (1 - log(tan(rad) + 1 / cos(rad)) / .pi) / 2 * scale
            let x = Int(worldX / 256), y = Int(worldY / 256)
            guard let alpha = tiles[x << 16 | y] else { return false }
            let px = min(255, max(0, Int(worldX) - x * 256))
            let py = min(255, max(0, Int(worldY) - y * 256))
            return alpha[py * 256 + px] > 16
        }

        /// Decode a 256 px tile and keep only its alpha channel (dry = transparent).
        private static func alphaPlane(from data: Data) -> [UInt8]? {
            guard let image = UIImage(data: data)?.cgImage else { return nil }
            var rgba = [UInt8](repeating: 0, count: 256 * 256 * 4)
            let ok = rgba.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(
                    data: raw.baseAddress, width: 256, height: 256, bitsPerComponent: 8,
                    bytesPerRow: 256 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256))
                return true
            }
            guard ok else { return nil }
            return (0..<256 * 256).map { rgba[$0 * 4 + 3] }
        }
    }

    // MARK: - Networking

    /// `freshest` skips the URL cache — frame lists go stale within minutes.
    /// (Per-frame tile URLs are immutable, so those cache freely.)
    nonisolated private static func fetchData(_ url: URL, freshest: Bool = false) async -> Data? {
        var request = URLRequest(url: url)
        if freshest { request.cachePolicy = .reloadIgnoringLocalCacheData }
        request.timeoutInterval = 20
        request.addAPIContactIdentity()
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true
        else { return nil }
        return data
    }

    // MARK: - Geo helpers

    private struct GeoBox {
        let south, west, north, east: Double

        func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
            coordinate.latitude >= south && coordinate.latitude <= north
                && coordinate.longitude >= west && coordinate.longitude <= east
        }
    }

    /// Linear Web-Mercator mapping between a coordinate rectangle and composite
    /// points — the CPU analog of the basemap snapshot's point conversion.
    private struct MercatorFrame {
        let x0, x1: Double // world-fraction X at west/east
        let y0, y1: Double // world-fraction Y at north/south
        let size: CGSize

        init(bounds: GeoBox, size: CGSize) {
            x0 = (bounds.west + 180) / 360
            x1 = (bounds.east + 180) / 360
            y0 = Self.worldY(bounds.north)
            y1 = Self.worldY(bounds.south)
            self.size = size
        }

        static func worldY(_ latitude: Double) -> Double {
            let rad = latitude * .pi / 180
            return (1 - log(tan(rad) + 1 / cos(rad)) / .pi) / 2
        }

        func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
            point(forWorldX: (coordinate.longitude + 180) / 360, worldY: Self.worldY(coordinate.latitude))
        }

        func point(forWorldX wx: Double, worldY wy: Double) -> CGPoint {
            CGPoint(
                x: (wx - x0) / (x1 - x0) * size.width,
                y: (wy - y0) / (y1 - y0) * size.height
            )
        }
    }

    /// The coordinate rectangle a bounds-fitted snapshot of `size` would show: the
    /// 65 km box extended along one axis to the size's aspect ratio in Mercator
    /// space. Used only when no prerendered basemap exists yet.
    nonisolated private static func fittedBounds(
        around center: CLLocationCoordinate2D, spanMeters: Double, size: CGSize
    ) -> GeoBox {
        let box = boundingBox(around: center, spanMeters: spanMeters)
        var west = (box.west + 180) / 360
        var east = (box.east + 180) / 360
        var north = MercatorFrame.worldY(box.north)
        var south = MercatorFrame.worldY(box.south)
        let aspect = Double(size.width / size.height)
        let width = east - west, height = south - north
        if width / height < aspect {
            let extra = (height * aspect - width) / 2
            west -= extra
            east += extra
        } else {
            let extra = (width / aspect - height) / 2
            north -= extra
            south += extra
        }
        func latitude(fromWorldY wy: Double) -> Double {
            (2 * atan(exp(.pi * (1 - 2 * wy))) - .pi / 2) * 180 / .pi
        }
        return GeoBox(
            south: latitude(fromWorldY: south), west: west * 360 - 180,
            north: latitude(fromWorldY: north), east: east * 360 - 180
        )
    }

    nonisolated private static func boundingBox(around center: CLLocationCoordinate2D, spanMeters: Double) -> GeoBox {
        let halfLat = spanMeters / 2 / 111_320
        let halfLon = spanMeters / 2 / (111_320 * max(0.2, cos(center.latitude * .pi / 180)))
        return GeoBox(
            south: center.latitude - halfLat, west: center.longitude - halfLon,
            north: center.latitude + halfLat, east: center.longitude + halfLon
        )
    }

    nonisolated private static func mercatorY(_ latitude: Double) -> Double {
        log(tan(.pi / 4 + latitude * .pi / 360))
    }

    nonisolated private static func latitudeFromMercatorY(_ y: Double) -> Double {
        (2 * atan(exp(y)) - .pi / 2) * 180 / .pi
    }

    nonisolated private static func tileX(_ longitude: Double, zoom: Int) -> Int {
        Int(floor((longitude + 180) / 360 * pow(2, Double(zoom))))
    }

    nonisolated private static func tileY(_ latitude: Double, zoom: Int) -> Int {
        let rad = latitude * .pi / 180
        return Int(floor((1 - log(tan(rad) + 1 / cos(rad)) / .pi) / 2 * pow(2, Double(zoom))))
    }

    nonisolated(unsafe) private static let fractionalDateParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let plainDateParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated private static func parsedDate(from timestamp: String) -> Date? {
        fractionalDateParser.date(from: timestamp)
            ?? plainDateParser.date(from: timestamp)
            ?? Double(timestamp).map { Date(timeIntervalSince1970: $0) }
    }
}

// MARK: - Overlay plan

private struct RadarOverlayPlan {
    var tileURLTemplate: String?
    var maximumTileZoom: Float = 10
    var frameDate: Date?
    var arrows: [RadarArrow] = []
}

private struct RadarArrow {
    let coordinate: CLLocationCoordinate2D
    let rotation: Double
    let scale: Double
}

// MARK: - API models

private struct RadarFramesResponse: Decodable {
    let frames: [RadarFrameInfo]
    let bounds: BoundsDTO?
    let imageBounds: BoundsDTO?

    enum CodingKeys: String, CodingKey {
        case frames
        case bounds
        case imageBounds = "image_bounds"
    }
}

private struct RadarFrameInfo: Decodable {
    let key: String
    let timestamp: String
}

private struct ModelFramesResponse: Decodable {
    let frames: [ModelFrameInfo]
}

private struct ModelFrameInfo: Decodable {
    let key: String
    let validTime: String
}

private struct BoundsDTO: Decodable {
    let north: Double
    let south: Double
    let west: Double
    let east: Double

    var asDomain: OscarRadarBounds {
        OscarRadarBounds(north: north, south: south, west: west, east: east)
    }
}
