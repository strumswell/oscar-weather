//
//  WidgetBasemapRenderer.swift
//  Oscar°
//
//  Prerenders the radar widget's basemap in the APP process. iOS denies GPU work
//  to widget extensions on device ("Insufficient Permission to submit GPU work
//  from background"), so MLNMapSnapshotter can only run here, while the app is
//  foreground. The widget composites live radar tiles over the cached PNG on the
//  CPU (RadarSnapshotRenderer in the widget target).
//

import CoreLocation
import MapLibre
import UIKit
import WidgetKit

@MainActor
enum WidgetBasemapRenderer {
    /// Shared with RadarProvider.snapshotSize in the widget (same store keys).
    private static let sizes = WidgetBasemapStore.compositeSizes
    /// Same framing as the widget compositor / in-app map.
    private static let spanMeters = 65_000.0
    private static let scale: CGFloat = 2
    /// Re-render when the location moved past this or the cache got old.
    private static let maxLocationDrift: CLLocationDistance = 500
    private static let maxAge: TimeInterval = 30 * 24 * 3600

    private static var isRefreshing = false

    /// Renders any missing/stale basemaps for the current location and reloads the
    /// radar widget when something new landed. Cheap when the cache is warm.
    /// One basemap per (size, style) — styles come from the widget instances'
    /// intent configurations via the app-group handshake (a style newly picked in
    /// a widget renders over the flat fallback until the app runs this).
    static func refreshIfNeeded() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        LocationService.shared.update()
        let center = LocationService.shared.getCoordinates()
        guard CLLocationCoordinate2DIsValid(center) else { return }

        var rendered = false
        for styleRaw in WidgetBasemapStore.requestedStyles() {
            guard let style = MapBasemapStyle(rawValue: styleRaw) else { continue }
            for size in sizes {
                if let (record, _) = WidgetBasemapStore.load(size: size, style: styleRaw),
                   Date().timeIntervalSince(record.renderedAt) < maxAge,
                   CLLocation(latitude: record.latitude, longitude: record.longitude).distance(
                       from: CLLocation(latitude: center.latitude, longitude: center.longitude)
                   ) < maxLocationDrift {
                    continue
                }
                guard let result = try? await snapshot(
                    center: center, size: size, style: style) else { continue }
                WidgetBasemapStore.save(result.record, image: result.image)
                rendered = true
            }
        }
        if rendered {
            WidgetCenter.shared.reloadTimelines(ofKind: "WeatherWidget")
        }
    }

    private static func snapshot(
        center: CLLocationCoordinate2D, size: CGSize, style: MapBasemapStyle
    ) async throws -> (record: WidgetBasemapRecord, image: UIImage) {
        let options = MLNMapSnapshotOptions(
            styleURL: style.styleURL,
            camera: MLNMapCamera(lookingAtCenter: center, altitude: spanMeters, pitch: 0, heading: 0),
            size: size
        )
        let halfLat = spanMeters / 2 / 111_320
        let halfLon = spanMeters / 2 / (111_320 * max(0.2, cos(center.latitude * .pi / 180)))
        options.coordinateBounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: center.latitude - halfLat, longitude: center.longitude - halfLon),
            ne: CLLocationCoordinate2D(latitude: center.latitude + halfLat, longitude: center.longitude + halfLon)
        )
        options.scale = scale
        options.showsLogo = false
        // OpenFreeMap/OSM attribution is covered by the map ⓘ + SettingsView.
        options.showsAttribution = false

        let run = SnapshotRun(snapshotter: MLNMapSnapshotter(options: options))
        let scale = scale
        return try await withCheckedThrowingContinuation { continuation in
            // A cancelled snapshotter never calls back, so the timeout resumes.
            run.timeout = Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, run.finish() else { return }
                run.snapshotter.cancel()
                continuation.resume(throwing: URLError(.timedOut))
            }
            run.snapshotter.start { snapshot, error in
                // The snapshot's own corner conversion captures the ACTUAL rendered
                // rectangle (coordinateBounds gets extended to the size's aspect) —
                // the widget relies on it for pixel-exact overlay math. Read it here
                // so only Sendable values cross into the main-actor block.
                let rendered = snapshot.map { snapshot in
                    (nw: snapshot.coordinate(for: .zero),
                     se: snapshot.coordinate(for: CGPoint(x: size.width, y: size.height)),
                     image: snapshot.image)
                }
                // MapLibre delivers the completion on the main queue.
                MainActor.assumeIsolated {
                    guard run.finish() else { return }
                    run.timeout?.cancel()
                    guard let rendered else {
                        continuation.resume(throwing: error ?? URLError(.unknown))
                        return
                    }
                    let record = WidgetBasemapRecord(
                        latitude: center.latitude, longitude: center.longitude,
                        north: rendered.nw.latitude, south: rendered.se.latitude,
                        west: rendered.nw.longitude, east: rendered.se.longitude,
                        width: size.width, height: size.height, scale: scale,
                        renderedAt: Date(), style: style.rawValue
                    )
                    continuation.resume(returning: (record, rendered.image))
                }
            }
        }
    }

    /// One snapshot request: retains the snapshotter and makes sure exactly one
    /// of completion and timeout resumes the continuation.
    @MainActor
    private final class SnapshotRun {
        let snapshotter: MLNMapSnapshotter
        var timeout: Task<Void, Never>?
        private var finished = false

        init(snapshotter: MLNMapSnapshotter) { self.snapshotter = snapshotter }

        /// True for the first caller only.
        func finish() -> Bool {
            if finished { return false }
            finished = true
            return true
        }
    }
}
