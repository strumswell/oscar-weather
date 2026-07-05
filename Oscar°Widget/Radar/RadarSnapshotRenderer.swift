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

/// Per-widget render options, straight from the configuration intent.
struct RadarWidgetRenderOptions {
    var style: String = WidgetBasemapStore.defaultStyle
    var smoothing = true
    var motionArrows = true
    var stormCells = false
}

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

    /// Fallback canvas when no basemap has been prerendered yet for the widget's
    /// style (app not opened since install / location or style change) — each
    /// style's land tone.
    private static func fallbackBackground(style: String) -> UIColor {
        switch style {
        case "dark": UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        case "positron": UIColor(red: 0.94, green: 0.94, blue: 0.93, alpha: 1)
        default: UIColor(red: 0.20, green: 0.22, blue: 0.28, alpha: 1)
        }
    }

    // MARK: - Entry point

    /// Composites the widget map for a location. Returns nil only when there is
    /// neither a cached basemap nor any precip data (e.g. offline on first run) —
    /// the provider then shows its connectivity fallback.
    static func render(
        center: CLLocationCoordinate2D, size: CGSize,
        options: RadarWidgetRenderOptions = RadarWidgetRenderOptions()
    ) async -> Rendered? {
        let region = RadarRegion.bestSource(latitude: center.latitude, longitude: center.longitude)
        let plan: RadarOverlayPlan
        if let region {
            plan = await radarPlan(region: region, around: center, includeArrows: options.motionArrows)
        } else {
            plan = await gfsPlan()
        }

        var cells: [WidgetStormCell] = []
        if options.stormCells, let region {
            cells = await stormCells(region: region, around: center)
        }

        let basemap = loadBasemap(center: center, size: size, style: options.style)
        guard basemap != nil || plan.tileURLTemplate != nil else { return nil }

        let bounds = basemap?.bounds ?? fittedBounds(around: center, spanMeters: mapSpanMeters, size: size)
        let frame = MercatorFrame(bounds: bounds, size: size)
        let tiles = await fetchOverlayTiles(plan: plan, frame: frame)

        var smoothed: UIImage?
        if options.smoothing, let colormapId = plan.colormapId,
           let palette = await palette(id: colormapId) {
            smoothed = dataSmoothedOverlay(tiles: tiles, frame: frame, palette: palette)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = compositeScale
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            if let basemap {
                basemap.image.draw(in: CGRect(origin: .zero, size: size))
            } else {
                fallbackBackground(style: options.style).setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            if let smoothed {
                smoothed.draw(in: CGRect(origin: .zero, size: size),
                              blendMode: .normal, alpha: radarOverlayAlpha)
            } else {
                context.cgContext.interpolationQuality = options.smoothing ? .default : .none
                for tile in tiles {
                    tile.image.draw(in: tile.rect, blendMode: .normal, alpha: radarOverlayAlpha)
                }
                context.cgContext.interpolationQuality = .default
            }
            drawArrows(plan.arrows, frame: frame, context: context.cgContext)
            drawStormCells(cells, frame: frame)
            drawLocationMarker(at: frame.point(for: center))
        }
        return Rendered(image: image, frameDate: plan.frameDate)
    }

    /// Precip overlay alone (tiles of the frame closest to now; regional radar in
    /// coverage, GFS precip elsewhere), projected into a `size`-pt viewport spanning
    /// `spanMeters` around `center`. For widgets that draw their own basemap
    /// (GlobalRadarWidget's MKMapSnapshotter) instead of the app-group prerender.
    static func overlayImage(
        center: CLLocationCoordinate2D, spanMeters: Double, size: CGSize
    ) async -> UIImage? {
        let plan: RadarOverlayPlan
        if let region = RadarRegion.bestSource(latitude: center.latitude, longitude: center.longitude) {
            plan = await radarPlan(region: region, around: center, includeArrows: false)
        } else {
            plan = await gfsPlan()
        }
        guard plan.tileURLTemplate != nil else { return nil }
        let bounds = fittedBounds(around: center, spanMeters: spanMeters, size: size)
        let frame = MercatorFrame(bounds: bounds, size: size)
        let tiles = await fetchOverlayTiles(plan: plan, frame: frame)
        guard !tiles.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = compositeScale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            for tile in tiles {
                tile.image.draw(in: tile.rect)
            }
        }
    }

    // MARK: - Basemap

    private static func loadBasemap(
        center: CLLocationCoordinate2D, size: CGSize, style: String
    ) -> (image: UIImage, bounds: GeoBox)? {
        guard let (record, image) = WidgetBasemapStore.load(size: size, style: style) else { return nil }
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
    private static func radarPlan(
        region: RadarRegion, around center: CLLocationCoordinate2D, includeArrows: Bool = true
    ) async -> RadarOverlayPlan {
        guard let url = URL(string: "\(radarBaseURL)/radar/\(region.pathComponent)/frames"),
              let data = await fetchData(url, freshest: true),
              let response = try? JSONDecoder().decode(RadarFramesResponse.self, from: data),
              let frame = closestFrame(in: response.frames.map { ($0.key, $0.timestamp) })
        else { return RadarOverlayPlan() }

        var plan = RadarOverlayPlan(
            tileURLTemplate: "\(radarBaseURL)/radar/\(region.pathComponent)/frames/\(frame.key)/tiles/{z}/{x}/{y}",
            maximumTileZoom: 10,
            frameDate: frame.date,
            colormapId: RadarProduct.precipitation.colormapId
        )

        let bounds = (response.imageBounds ?? response.bounds).asDomain
        if includeArrows,
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
            frameDate: frame.date,
            colormapId: RadarProduct.precipitation.colormapId  // GFS precip shares plasma
        )
    }

    nonisolated private static func closestFrame(in frames: [(key: String, timestamp: String)]) -> (key: String, date: Date)? {
        let now = Date()
        return frames
            .compactMap { frame in parseFrameDate(frame.timestamp).map { (frame.key, $0) } }
            .min { abs(now.timeIntervalSince($0.1)) < abs(now.timeIntervalSince($1.1)) }
    }

    // MARK: - Overlay tiles

    private struct OverlayTile {
        let rect: CGRect
        let image: UIImage
        /// Web-Mercator tile address — the smoothing resample stitches tiles into
        /// one index mosaic and needs their grid positions.
        let zoom: Int
        let tx: Int
        let ty: Int
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
                    image: image,
                    zoom: zoom, tx: tx, ty: ty
                ))
            }
        }
        return tiles
    }

    // MARK: - Drawing

    private static func drawArrows(_ arrows: [RadarArrow], frame: MercatorFrame, context: CGContext) {
        guard !arrows.isEmpty else { return }
        let icon = RadarArrowGeometry.arrowImage()
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

    // MARK: - Smoothing (data-space, mirrors the fullscreen layer)

    /// The app's "Weichzeichnen", CPU edition. The fullscreen Metal layer samples
    /// the value grid with a bicubic B-spline and colormaps AFTER interpolation
    /// through a premultiplied palette LUT with linear blending. Blurring the
    /// colormapped tiles instead looks visibly different (off-palette color blends,
    /// softened alpha rims), so this reverses the tiles to palette indices, runs
    /// the same B-spline resample in data space, and recolormaps.
    private static var cachedPalettes: [String: [PixelRGBA]] = [:]

    private static func palette(id: String) async -> [PixelRGBA]? {
        if let cached = cachedPalettes[id] { return cached }
        guard let url = URL(string: "\(radarBaseURL)/colormaps/\(id)"),
              let data = await fetchData(url), data.count >= 256 * 4 else { return nil }
        let palette = (0..<256).map { entry -> PixelRGBA in
            let o = entry * 4
            return PixelRGBA(r: data[o], g: data[o + 1], b: data[o + 2], a: data[o + 3])
        }
        cachedPalettes[id] = palette
        return palette
    }

    private static func dataSmoothedOverlay(
        tiles: [OverlayTile], frame: MercatorFrame, palette: [PixelRGBA]
    ) -> UIImage? {
        guard let zoom = tiles.first?.zoom, !tiles.isEmpty else { return nil }
        let n = pow(2, Double(zoom))

        // Premultiplied palette, like the Metal layer's LUT texture — index
        // reversal and linear blending both happen in premultiplied space.
        let premul: [(r: Double, g: Double, b: Double, a: Double)] = palette.map { entry in
            let a = Double(entry.a) / 255
            return (Double(entry.r) * a, Double(entry.g) * a, Double(entry.b) * a, Double(entry.a))
        }
        var reverseLUT: [UInt32: UInt8] = [:]
        for (index, entry) in premul.enumerated().reversed() {
            let key = UInt32(entry.r.rounded()) << 24 | UInt32(entry.g.rounded()) << 16
                | UInt32(entry.b.rounded()) << 8 | UInt32(entry.a.rounded())
            reverseLUT[key] = UInt8(index)
        }

        // Stitch the tiles' index planes into one mosaic (0 = no data/dry).
        let minX = tiles.map(\.tx).min()!, maxX = tiles.map(\.tx).max()!
        let minY = tiles.map(\.ty).min()!, maxY = tiles.map(\.ty).max()!
        let mosaicW = (maxX - minX + 1) * 256
        let mosaicH = (maxY - minY + 1) * 256
        var mosaic = [UInt8](repeating: 0, count: mosaicW * mosaicH)
        var nearestMemo: [UInt32: UInt8] = [:]
        for tile in tiles {
            guard let rgba = rgbaPlane(from: tile.image) else { continue }
            let originX = (tile.tx - minX) * 256
            let originY = (tile.ty - minY) * 256
            for py in 0..<256 {
                let src = py * 256 * 4
                let dst = (originY + py) * mosaicW + originX
                for px in 0..<256 {
                    let o = src + px * 4
                    let a = rgba[o + 3]
                    if a == 0 { continue }
                    let key = UInt32(rgba[o]) << 24 | UInt32(rgba[o + 1]) << 16
                        | UInt32(rgba[o + 2]) << 8 | UInt32(a)
                    if let index = reverseLUT[key] {
                        mosaic[dst + px] = index
                    } else if let index = nearestMemo[key] {
                        mosaic[dst + px] = index
                    } else {
                        // Off-palette color (server-side resampling rounding):
                        // nearest premultiplied entry, memoized per distinct color.
                        var best = 0
                        var bestDistance = Double.infinity
                        for (index, entry) in premul.enumerated() {
                            let dr = entry.r - Double(rgba[o])
                            let dg = entry.g - Double(rgba[o + 1])
                            let db = entry.b - Double(rgba[o + 2])
                            let da = entry.a - Double(a)
                            let distance = dr * dr + dg * dg + db * db + da * da
                            if distance < bestDistance {
                                bestDistance = distance
                                best = index
                            }
                        }
                        nearestMemo[key] = UInt8(best)
                        mosaic[dst + px] = UInt8(best)
                    }
                }
            }
        }

        // Resample in data space at composite resolution: bicubic B-spline over
        // the index mosaic (Sigg & Hadwiger weights, same as the shader), then
        // linear palette blend — colormap strictly after interpolation.
        let outW = Int(frame.size.width * compositeScale)
        let outH = Int(frame.size.height * compositeScale)
        guard outW > 0, outH > 0 else { return nil }
        var out = [UInt8](repeating: 0, count: outW * outH * 4)

        @inline(__always) func bsplineWeights(_ t: Double) -> (Double, Double, Double, Double) {
            let t2 = t * t, t3 = t2 * t
            return ((1 - 3 * t + 3 * t2 - t3) / 6,
                    (4 - 6 * t2 + 3 * t3) / 6,
                    (1 + 3 * t + 3 * t2 - 3 * t3) / 6,
                    t3 / 6)
        }

        mosaic.withUnsafeBufferPointer { indices in
            out.withUnsafeMutableBufferPointer { pixels in
                for py in 0..<outH {
                    let wy = frame.y0 + (Double(py) + 0.5) / Double(outH) * (frame.y1 - frame.y0)
                    let my = (wy * n - Double(minY)) * 256 - 0.5
                    guard my > -1, my < Double(mosaicH) else { continue }
                    let iy = Int(my.rounded(.down))
                    let (wy0, wy1, wy2, wy3) = bsplineWeights(my - Double(iy))
                    let rowWeights = [wy0, wy1, wy2, wy3]

                    for px in 0..<outW {
                        let wx = frame.x0 + (Double(px) + 0.5) / Double(outW) * (frame.x1 - frame.x0)
                        let mx = (wx * n - Double(minX)) * 256 - 0.5
                        guard mx > -1, mx < Double(mosaicW) else { continue }
                        let ix = Int(mx.rounded(.down))
                        let (wx0, wx1, wx2, wx3) = bsplineWeights(mx - Double(ix))
                        let columnWeights = [wx0, wx1, wx2, wx3]

                        var value = 0.0
                        for row in 0..<4 {
                            let sy = min(max(iy - 1 + row, 0), mosaicH - 1)
                            let rowBase = sy * mosaicW
                            var rowValue = 0.0
                            for column in 0..<4 {
                                let sx = min(max(ix - 1 + column, 0), mosaicW - 1)
                                rowValue += columnWeights[column] * Double(indices[rowBase + sx])
                            }
                            value += rowWeights[row] * rowValue
                        }
                        guard value > 0.01 else { continue }

                        let clamped = min(max(value, 0), 255)
                        let i0 = Int(clamped)
                        let i1 = min(255, i0 + 1)
                        let f = clamped - Double(i0)
                        let e0 = premul[i0], e1 = premul[i1]
                        let o = (py * outW + px) * 4
                        pixels[o]     = UInt8((e0.r + (e1.r - e0.r) * f).rounded())
                        pixels[o + 1] = UInt8((e0.g + (e1.g - e0.g) * f).rounded())
                        pixels[o + 2] = UInt8((e0.b + (e1.b - e0.b) * f).rounded())
                        pixels[o + 3] = UInt8((e0.a + (e1.a - e0.a) * f).rounded())
                    }
                }
            }
        }

        let cgImage: CGImage? = out.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: outW, height: outH, bitsPerComponent: 8,
                bytesPerRow: outW * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }
        guard let cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: compositeScale, orientation: .up)
    }

    /// Decode a 256 px tile into premultiplied RGBA bytes.
    private static func rgbaPlane(from image: UIImage) -> [UInt8]? {
        guard let cgImage = image.cgImage else { return nil }
        var rgba = [UInt8](repeating: 0, count: 256 * 256 * 4)
        let ok = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: 256, height: 256, bitsPerComponent: 8,
                bytesPerRow: 256 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: 256, height: 256))
            return true
        }
        return ok ? rgba : nil
    }

    // MARK: - Storm cells (server /radar/{region}/cells, SCIT tracks)

    private struct WidgetStormCell {
        let center: CLLocationCoordinate2D
        let peakMmh: Double
        let velocityKmh: Double
        /// Extrapolated centroids at +15/+30/+45/+60 min.
        let path: [CLLocationCoordinate2D]
        /// Convex-hull outline (closed ring); empty when the server sent none.
        let footprint: [CLLocationCoordinate2D]
    }

    private static func stormCells(
        region: RadarRegion, around center: CLLocationCoordinate2D
    ) async -> [WidgetStormCell] {
        struct CellsGeoJSON: Decodable {
            struct Feature: Decodable {
                struct Geometry: Decodable { let coordinates: [Double] }
                struct Properties: Decodable {
                    let peak_mmh: Double
                    let velocity_kmh: Double
                    let path: [[Double]]
                    let footprint: [[Double]]?
                }
                let geometry: Geometry
                let properties: Properties
            }
            let features: [Feature]
        }

        guard let url = URL(string: "\(radarBaseURL)/radar/\(region.pathComponent)/cells"),
              let data = await fetchData(url, freshest: true),
              let collection = try? JSONDecoder().decode(CellsGeoJSON.self, from: data)
        else { return [] }

        let cull = boundingBox(around: center, spanMeters: mapSpanMeters * 1.6)
        func coordinate(_ pair: [Double]) -> CLLocationCoordinate2D? {
            pair.count == 2
                ? CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0]) : nil
        }
        return collection.features.compactMap { feature in
            guard feature.geometry.coordinates.count == 2 else { return nil }
            let cellCenter = CLLocationCoordinate2D(
                latitude: feature.geometry.coordinates[1],
                longitude: feature.geometry.coordinates[0])
            guard cull.contains(cellCenter) else { return nil }
            return WidgetStormCell(
                center: cellCenter,
                peakMmh: feature.properties.peak_mmh,
                velocityKmh: feature.properties.velocity_kmh,
                path: feature.properties.path.compactMap(coordinate),
                footprint: (feature.properties.footprint ?? []).compactMap(coordinate))
        }
    }

    /// Widget-scale rendition of the app's cell overlay: footprint hull, dashed
    /// extrapolated track, and an intensity-colored marker at the cell core.
    private static func drawStormCells(_ cells: [WidgetStormCell], frame: MercatorFrame) {
        for cell in cells {
            let color = intensityColor(peakMmh: cell.peakMmh)

            if cell.footprint.count >= 4 {
                let hull = UIBezierPath()
                for (index, coordinate) in cell.footprint.enumerated() {
                    let point = frame.point(for: coordinate)
                    index == 0 ? hull.move(to: point) : hull.addLine(to: point)
                }
                hull.close()
                color.withAlphaComponent(0.15).setFill()
                hull.fill()
                color.withAlphaComponent(0.75).setStroke()
                hull.lineWidth = 1
                hull.stroke()
            }

            // Track only for cells that actually move — the app's rule.
            let trackPoints = [cell.center] + cell.path
            if cell.velocityKmh >= 3, trackPoints.count >= 2 {
                let track = UIBezierPath()
                track.move(to: frame.point(for: trackPoints[0]))
                for coordinate in trackPoints.dropFirst() {
                    track.addLine(to: frame.point(for: coordinate))
                }
                track.setLineDash([3, 2], count: 2, phase: 0)
                track.lineWidth = 1.5
                UIColor.white.withAlphaComponent(0.75).setStroke()
                track.stroke()
            }

            let point = frame.point(for: cell.center)
            let marker = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            color.setFill()
            UIBezierPath(ovalIn: marker).fill()
            let outline = UIBezierPath(ovalIn: marker)
            UIColor.white.withAlphaComponent(0.9).setStroke()
            outline.lineWidth = 1.5
            outline.stroke()
        }
    }

    /// The app's peak-intensity severity steps (WeatherMapView / StormCellLegend).
    private static func intensityColor(peakMmh: Double) -> UIColor {
        switch peakMmh {
        case ..<2: UIColor(red: 0, green: 0.79, blue: 0.79, alpha: 1)       // #00caca
        case ..<10: UIColor(red: 1, green: 1, blue: 0, alpha: 1)            // moderate
        case ..<50: UIColor(red: 1, green: 0, blue: 0, alpha: 1)            // heavy
        default: UIColor(red: 0.996, green: 0.2, blue: 1, alpha: 1)         // extreme
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

    // MARK: - Motion arrows (shares RadarArrowGeometry with WeatherMapView)

    /// One arrow per coarse motion cell that carries precipitation and non-trivial
    /// flow, culled to the widget's viewport. Identical placement math to the app
    /// (RadarArrowGeometry); only the precip gate differs (raster-tile alpha
    /// instead of the value grid).
    private static func arrowFeatures(
        motion: RadarMotionData, fieldIndex: Int, bounds: OscarRadarBounds,
        cull: GeoBox, gate: PrecipGate?
    ) -> [RadarArrow] {
        guard let gate else { return [] }
        let cols = motion.cols, rows = motion.rows
        let coordinate = RadarArrowGeometry.coordinateMapper(bounds: bounds)

        var arrows: [RadarArrow] = []
        for cell in RadarArrowGeometry.arrowCells(motion: motion, fieldIndex: fieldIndex, bounds: bounds) {
            guard cull.contains(cell.coordinate) else { continue }

            // ≥2 of 25 subsampled points inside the cell footprint carry precip —
            // the app's cellHasPrecip rule, sampled from the gate tiles.
            var hits = 0
            subsample: for sy in 0..<5 {
                for sx in 0..<5 {
                    let x = cell.uvX + (Double(sx) / 4 - 0.5) / Double(cols)
                    let y = cell.uvY + (Double(sy) / 4 - 0.5) / Double(rows)
                    guard x >= 0, x <= 1, y >= 0, y <= 1 else { continue }
                    if gate.hasPrecip(at: coordinate(x, y)) {
                        hits += 1
                        if hits >= 2 { break subsample }
                    }
                }
            }
            guard hits >= 2 else { continue }

            arrows.append(RadarArrow(coordinate: cell.coordinate, rotation: cell.rotation, scale: cell.scale))
            if arrows.count >= 80 { break }
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
            let x0 = WebMercator.tileX(longitude: box.west, zoom: gateZoom)
            let x1 = WebMercator.tileX(longitude: box.east, zoom: gateZoom)
            let y0 = WebMercator.tileY(latitude: box.north, zoom: gateZoom)
            let y1 = WebMercator.tileY(latitude: box.south, zoom: gateZoom)
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
            let worldX = WebMercator.unitX(longitude: coordinate.longitude) * scale
            let worldY = WebMercator.unitY(latitude: coordinate.latitude) * scale
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
            x0 = WebMercator.unitX(longitude: bounds.west)
            x1 = WebMercator.unitX(longitude: bounds.east)
            y0 = WebMercator.unitY(latitude: bounds.north)
            y1 = WebMercator.unitY(latitude: bounds.south)
            self.size = size
        }

        func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
            point(forWorldX: WebMercator.unitX(longitude: coordinate.longitude),
                  worldY: WebMercator.unitY(latitude: coordinate.latitude))
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
        var west = WebMercator.unitX(longitude: box.west)
        var east = WebMercator.unitX(longitude: box.east)
        var north = WebMercator.unitY(latitude: box.north)
        var south = WebMercator.unitY(latitude: box.south)
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
        return GeoBox(
            south: WebMercator.latitude(fromUnitY: south), west: WebMercator.longitude(fromUnitX: west),
            north: WebMercator.latitude(fromUnitY: north), east: WebMercator.longitude(fromUnitX: east)
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

}

// MARK: - Overlay plan

private struct RadarOverlayPlan {
    var tileURLTemplate: String?
    var maximumTileZoom: Float = 10
    var frameDate: Date?
    /// Server palette (`/colormaps/{id}`) the tile colors index into — needed to
    /// reverse tiles to data values for the smoothing resample.
    var colormapId: String?
    var arrows: [RadarArrow] = []
}

private struct RadarArrow {
    let coordinate: CLLocationCoordinate2D
    let rotation: Double
    let scale: Double
}
