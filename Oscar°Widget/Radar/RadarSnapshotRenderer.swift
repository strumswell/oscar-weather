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
//  else the global ECMWF precip forecast. Everything is fetched before compositing,
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
    static let mapSpanMeters = 65_000.0
    /// Matches the prerendered basemap PNGs.
    static let compositeScale: CGFloat = 2
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
            plan = await ecmwfPlan()
        }

        var cells: [WidgetStormCell] = []
        if options.stormCells, let region {
            cells = await stormCells(region: region, around: center)
        }

        let basemap = loadBasemap(center: center, size: size, style: options.style)
        guard basemap != nil || plan.tileSource != nil else { return nil }

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
    /// coverage, ECMWF precip elsewhere), projected into a `size`-pt viewport spanning
    /// `spanMeters` around `center`. For widgets that draw their own basemap
    /// (GlobalRadarWidget's MKMapSnapshotter) instead of the app-group prerender.
    static func overlayImage(
        center: CLLocationCoordinate2D, spanMeters: Double, size: CGSize
    ) async -> Rendered? {
        let plan: RadarOverlayPlan
        if let region = RadarRegion.bestSource(latitude: center.latitude, longitude: center.longitude) {
            plan = await radarPlan(region: region, around: center, includeArrows: false)
        } else {
            plan = await ecmwfPlan()
        }
        guard plan.tileSource != nil else { return nil }
        let bounds = fittedBounds(around: center, spanMeters: spanMeters, size: size)
        let frame = MercatorFrame(bounds: bounds, size: size)
        let tiles = await fetchOverlayTiles(plan: plan, frame: frame)
        guard !tiles.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = compositeScale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            for tile in tiles {
                tile.image.draw(in: tile.rect)
            }
        }
        return Rendered(image: image, frameDate: plan.frameDate)
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
        guard let response = try? await APIClient.shared.radarFrames(
                region: region.pathComponent, profile: .snapshot),
              let frame = closestFrame(in: response.frames.map { ($0.key, $0.timestamp) })
        else { return RadarOverlayPlan() }

        var plan = RadarOverlayPlan(
            tileSource: .radar(region: region, key: frame.key),
            maximumTileZoom: 10,
            frameDate: frame.date,
            colormapId: RadarPlasma.colormapId
        )

        let bounds = (response.image_bounds ?? response.bounds).asDomain
        if includeArrows,
           let motionResponse = try? await APIClient.shared.radarMotion(
                region: region.pathComponent, profile: .snapshot),
           let motion = RadarMotionData(payload: motionResponse),
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

    /// Global fallback outside all radar coverages: ECMWF precipitation forecast,
    /// frame closest to now. No motion fields — no arrows.
    private static func ecmwfPlan() async -> RadarOverlayPlan {
        guard let response = try? await APIClient.shared.modelFrames(
                model: "ecmwf", profile: .snapshot),
              let frame = closestFrame(in: response.frames.map { ($0.key, $0.validTime) })
        else { return RadarOverlayPlan() }

        return RadarOverlayPlan(
            tileSource: .ecmwfModel(key: frame.key),
            maximumTileZoom: 7,
            frameDate: frame.date,
            colormapId: RadarPlasma.colormapId // ECMWF precip shares plasma
        )
    }

    nonisolated private static func closestFrame(in frames: [(key: String, timestamp: String)]) -> (key: String, date: Date)? {
        let now = Date()
        return frames
            .compactMap { frame in parseFrameDate(frame.timestamp).map { (frame.key, $0) } }
            .min { abs(now.timeIntervalSince($0.1)) < abs(now.timeIntervalSince($1.1)) }
    }

    // MARK: - Overlay tiles

    struct OverlayTile {
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
        guard let source = plan.tileSource else { return [] }
        let worldWidth = frame.x1 - frame.x0
        guard worldWidth > 0 else { return [] }
        let pixelWidth = Double(frame.size.width) * Double(compositeScale)
        let idealZoom = Int(floor(log2(pixelWidth / 256 / worldWidth)))
        let zoom = max(0, min(Int(plan.maximumTileZoom), idealZoom))
        let n = pow(2, Double(zoom))

        let x0 = Int(floor(frame.x0 * n)), x1 = Int(floor(frame.x1 * n))
        let y0 = Int(floor(frame.y0 * n)), y1 = Int(floor(frame.y1 * n))
        guard x0 >= 0, y0 >= 0, (x1 - x0 + 1) * (y1 - y0 + 1) <= 16 else { return [] }

        var requests: [(tx: Int, ty: Int)] = []
        for tx in x0...x1 {
            for ty in y0...y1 {
                requests.append((tx, ty))
            }
        }

        return await withTaskGroup(of: OverlayTile?.self) { group in
            for request in requests {
                group.addTask {
                    let data: Data?
                    switch source {
                    case .radar(let region, let key):
                        data = try? await APIClient.shared.radarTile(
                            region: region.pathComponent, key: key, z: zoom, x: request.tx, y: request.ty,
                            profile: .snapshot)
                    case .ecmwfModel(let key):
                        data = try? await APIClient.shared.modelTile(
                            model: "ecmwf", key: key, variable: "precipitation",
                            z: zoom, x: request.tx, y: request.ty, profile: .snapshot)
                    }
                    guard let data, let image = UIImage(data: data) else { return nil }
                    let tx = request.tx
                    let ty = request.ty
                let origin = frame.point(forWorldX: Double(tx) / n, worldY: Double(ty) / n)
                let corner = frame.point(forWorldX: Double(tx + 1) / n, worldY: Double(ty + 1) / n)
                    return OverlayTile(
                    rect: CGRect(x: origin.x, y: origin.y, width: corner.x - origin.x, height: corner.y - origin.y),
                    image: image,
                    zoom: zoom, tx: tx, ty: ty
                    )
                }
            }
            var tiles: [OverlayTile] = []
            for await tile in group {
                if let tile { tiles.append(tile) }
            }
            return tiles
        }
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

}

// MARK: - Overlay plan

private struct RadarOverlayPlan {
    /// Which oscar-server endpoint family the plan's tiles come from — carries
    /// enough to address any tile of the chosen frame (region/key or model/key).
    enum TileSource {
        case radar(region: RadarRegion, key: String)
        case ecmwfModel(key: String)
    }
    var tileSource: TileSource?
    var maximumTileZoom: Float = 10
    var frameDate: Date?
    /// Server palette (`/colormaps/{id}`) the tile colors index into — needed to
    /// reverse tiles to data values for the smoothing resample.
    var colormapId: String?
    var arrows: [RadarArrow] = []
}

struct RadarArrow {
    let coordinate: CLLocationCoordinate2D
    let rotation: Double
    let scale: Double
}
