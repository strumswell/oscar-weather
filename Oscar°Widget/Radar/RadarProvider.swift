import WidgetKit
import SwiftUI
import MapKit
import UIKit

struct RadarEntry: TimelineEntry {
    let date: Date
    let frameDate: Date
    let image: UIImage
}

struct RadarProvider: TimelineProvider {
    let locationService = LocationService.shared
    let radarOverlayAlpha: CGFloat = 0.7
    let mapColorType: UIUserInterfaceStyle = .dark

    private static let baseURL = "https://radar.oscars.love"
    private static let mapSpanMeters = 65_000.0

    init() {
        locationService.update()
    }

    func placeholder(in context: Context) -> RadarEntry {
        RadarEntry(date: Date(), frameDate: Date(), image: UIImage(named: "rain")!)
    }

    func getSnapshot(in context: Context, completion: @escaping (RadarEntry) -> Void) {
        Task {
            completion(await buildWidgetEntry(displaySize: context.displaySize, family: context.family))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RadarEntry>) -> Void) {
        Task {
            let entry = await buildWidgetEntry(displaySize: context.displaySize, family: context.family)
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    // MARK: - Main compositor

    private func buildWidgetEntry(displaySize: CGSize, family: WidgetFamily) async -> RadarEntry {
        locationService.update()
        let location = locationService.getCoordinates()
        let region = MKCoordinateRegion(
            center: location,
            latitudinalMeters: Self.mapSpanMeters,
            longitudinalMeters: Self.mapSpanMeters
        )
        let renderSize = snapshotSize(for: displaySize, family: family)

        guard let (snapshot, mapImage) = await fetchSnapshot(region: region, size: renderSize) else {
            let fallback = UIImage(systemName: "wifi.exclamationmark") ?? UIImage()
            return RadarEntry(date: Date(), frameDate: Date(), image: fallback)
        }

        guard let frame = await fetchLatestOscarFrame() else {
            return RadarEntry(
                date: Date(),
                frameDate: Date(),
                image: drawLocationMarker(on: mapImage, at: snapshot, coordinate: location)
            )
        }

        let radarTileZoom = resolvedRadarTileZoom(snapshot: snapshot, region: region)
        let tileSpecs = computeTileSpecs(
            snapshot: snapshot,
            region: region,
            zoom: radarTileZoom,
            frameKey: frame.key,
            path: "radar/tiles"
        )
        let arrowTileZoom = resolvedArrowTileZoom(snapshot: snapshot, region: region)
        let arrowTileSpecs = computeTileSpecs(
            snapshot: snapshot,
            region: region,
            zoom: arrowTileZoom,
            frameKey: frame.key,
            path: "radar/vector-tiles"
        )

        let radarTiles = await fetchRadarTiles(tileSpecs: tileSpecs)
        guard !radarTiles.isEmpty else {
            return RadarEntry(
                date: Date(),
                frameDate: frame.timestampDate ?? Date(),
                image: drawLocationMarker(on: mapImage, at: snapshot, coordinate: location)
            )
        }
        let arrowTiles = await fetchRadarTiles(tileSpecs: arrowTileSpecs, limit: 8)

        let size = mapImage.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = mapImage.scale
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            mapImage.draw(at: .zero)
            for tile in radarTiles {
                tile.image.draw(in: tile.rect, blendMode: .normal, alpha: radarOverlayAlpha)
            }
            for tile in arrowTiles {
                tile.image.draw(in: tile.rect, blendMode: .normal, alpha: 1.0)
            }
        }

        return RadarEntry(
            date: Date(),
            frameDate: frame.timestampDate ?? Date(),
            image: drawLocationMarker(on: image, at: snapshot, coordinate: location)
        )
    }

    // MARK: - Map snapshot

    private func fetchSnapshot(
        region: MKCoordinateRegion,
        size: CGSize
    ) async -> (MKMapSnapshotter.Snapshot, UIImage)? {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = await UIScreen.main.scale
        options.traitCollection = UITraitCollection(userInterfaceStyle: mapColorType)

        return await withCheckedContinuation { continuation in
            MKMapSnapshotter(options: options).start { snapshot, _ in
                guard let snapshot else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (snapshot, snapshot.image))
            }
        }
    }

    // MARK: - Oscar radar

    private func fetchLatestOscarFrame() async -> OscarWidgetRadarFrame? {
        guard let url = URL(string: "\(Self.baseURL)/radar/frames") else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.addAPIContactIdentity()

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(OscarFramesResponse.self, from: data),
              !response.frames.isEmpty
        else { return nil }

        // Pick the frame closest to now
        let now = Date()
        let best = response.frames.min {
            let a = parsedDate(from: $0.timestamp) ?? .distantPast
            let b = parsedDate(from: $1.timestamp) ?? .distantPast
            return abs(now.timeIntervalSince(a)) < abs(now.timeIntervalSince(b))
        }
        guard let frame = best else { return nil }
        return OscarWidgetRadarFrame(
            key: frame.key,
            timestamp: frame.timestamp,
            bounds: response.bounds
        )
    }

    private func parsedDate(from timestamp: String) -> Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return withFractionalSeconds.date(from: timestamp)
            ?? plain.date(from: timestamp)
            ?? Double(timestamp).map { Date(timeIntervalSince1970: $0) }
    }

    private func snapshotSize(for displaySize: CGSize, family: WidgetFamily) -> CGSize {
        switch family {
        case .systemLarge:
            return CGSize(width: 360, height: 170)
        default:
            return CGSize(width: 170, height: 170)
        }
    }

    private struct TileSpec {
        let url: URL
        let rect: CGRect
    }

    private struct RadarTile {
        let rect: CGRect
        let image: UIImage
    }

    private func resolvedRadarTileZoom(
        snapshot: MKMapSnapshotter.Snapshot,
        region: MKCoordinateRegion
    ) -> Int {
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLat = region.center.latitude - region.span.latitudeDelta / 2

        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: minLon))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: maxLon))
        let visibleWidth = max(abs(se.x - nw.x), 1.0)
        let visibleHeight = max(abs(se.y - nw.y), 1.0)

        let zoomScaleX = Double(snapshot.image.size.width) / visibleWidth
        let zoomScaleY = Double(snapshot.image.size.height) / visibleHeight
        let mapZoomScale = max(min(zoomScaleX, zoomScaleY), 0.000_001)
        let zoom = log2(Double(mapZoomScale * MKMapSize.world.width / 256.0))
        return max(0, min(10, Int(floor(zoom))))
    }

    private func resolvedArrowTileZoom(
        snapshot: MKMapSnapshotter.Snapshot,
        region: MKCoordinateRegion
    ) -> Int {
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLat = region.center.latitude - region.span.latitudeDelta / 2

        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: minLon))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: maxLon))
        let visibleWidth = max(abs(se.x - nw.x), 1.0)
        let visibleHeight = max(abs(se.y - nw.y), 1.0)

        let pixelWidth = Double(snapshot.image.size.width * snapshot.image.scale)
        let pixelHeight = Double(snapshot.image.size.height * snapshot.image.scale)
        let zoomScaleX = pixelWidth / visibleWidth
        let zoomScaleY = pixelHeight / visibleHeight
        let mapZoomScale = max(min(zoomScaleX, zoomScaleY), 0.000_001)
        let zoom = log2(Double(mapZoomScale * MKMapSize.world.width / 256.0))
        return max(0, min(12, Int(floor(zoom))))
    }

    private func computeTileSpecs(
        snapshot: MKMapSnapshotter.Snapshot,
        region: MKCoordinateRegion,
        zoom: Int,
        frameKey: String,
        path: String
    ) -> [TileSpec] {
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLat = region.center.latitude - region.span.latitudeDelta / 2

        let x0 = tileX(minLon, zoom: zoom)
        let x1 = tileX(maxLon, zoom: zoom)
        let y0 = tileY(maxLat, zoom: zoom)
        let y1 = tileY(minLat, zoom: zoom)

        var specs: [TileSpec] = []
        for tx in x0...max(x0, x1) {
            for ty in y0...max(y0, y1) {
                let nLat = Self.tileToLat(ty, zoom: zoom)
                let sLat = Self.tileToLat(ty + 1, zoom: zoom)
                let wLon = Self.tileToLon(tx, zoom: zoom)
                let eLon = Self.tileToLon(tx + 1, zoom: zoom)
                let nw = snapshot.point(for: CLLocationCoordinate2D(latitude: nLat, longitude: wLon))
                let se = snapshot.point(for: CLLocationCoordinate2D(latitude: sLat, longitude: eLon))
                let rect = CGRect(x: nw.x, y: nw.y, width: se.x - nw.x, height: se.y - nw.y)

                guard let url = URL(string: "\(Self.baseURL)/\(path)/\(frameKey)/\(zoom)/\(tx)/\(ty).webp") else {
                    continue
                }
                specs.append(TileSpec(url: url, rect: rect))
            }
        }
        return specs
    }

    private func fetchRadarTiles(tileSpecs: [TileSpec], limit: Int = 12) async -> [RadarTile] {
        var tiles: [RadarTile] = []
        for spec in tileSpecs.prefix(limit) {
            var request = URLRequest(url: spec.url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            request.addAPIContactIdentity()

            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let image = UIImage(data: data) else {
                continue
            }
            tiles.append(RadarTile(rect: spec.rect, image: image))
        }
        return tiles
    }

    private func tileX(_ lon: Double, zoom: Int) -> Int {
        Int(floor((lon + 180) / 360 * pow(2, Double(zoom))))
    }

    private func tileY(_ lat: Double, zoom: Int) -> Int {
        let rad = lat * .pi / 180
        return Int(floor((1 - log(tan(rad) + 1 / cos(rad)) / .pi) / 2 * pow(2, Double(zoom))))
    }

    private static func tileToLon(_ x: Int, zoom: Int) -> Double {
        Double(x) / pow(2, Double(zoom)) * 360 - 180
    }

    private static func tileToLat(_ y: Int, zoom: Int) -> Double {
        let n = .pi - 2 * .pi * Double(y) / pow(2, Double(zoom))
        return atan(sinh(n)) * 180 / .pi
    }

    private func drawLocationMarker(
        on image: UIImage,
        at snapshot: MKMapSnapshotter.Snapshot,
        coordinate: CLLocationCoordinate2D
    ) -> UIImage {
        let point = snapshot.point(for: coordinate)
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(at: .zero)

            let outerRect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
            UIColor.systemBlue.setFill()
            UIBezierPath(ovalIn: outerRect).fill()

            let innerRect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
            let outline = UIBezierPath(ovalIn: innerRect)
            UIColor.white.withAlphaComponent(0.8).setStroke()
            outline.lineWidth = 2
            outline.stroke()
        }
    }

}

// MARK: - API models

private struct OscarFramesResponse: Decodable {
    let frames: [OscarFrameInfo]
    let bounds: OscarBounds
}

private struct OscarFrameInfo: Decodable {
    let key: String
    let timestamp: String
}

private struct OscarWidgetRadarFrame {
    let key: String
    let timestamp: String
    let bounds: OscarBounds

    var timestampDate: Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return withFractionalSeconds.date(from: timestamp)
            ?? plain.date(from: timestamp)
            ?? Double(timestamp).map { Date(timeIntervalSince1970: $0) }
    }
}

private struct OscarBounds: Decodable {
    let north: Double
    let south: Double
    let west: Double
    let east: Double
}

extension MKCoordinateRegion {
    static func region(for location: CLLocationCoordinate2D, zoomLevel: Int) -> MKCoordinateRegion {
        let meters = 75_000.0 / pow(2, Double(zoomLevel - 1))
        return MKCoordinateRegion(center: location, latitudinalMeters: meters, longitudinalMeters: meters)
    }
}
