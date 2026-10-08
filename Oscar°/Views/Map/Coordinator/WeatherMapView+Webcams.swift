import CoreLocation
import MapLibre
import OSLog
import UIKit

// MARK: Webcam markers

extension WeatherMapView.Coordinator {
    /// The visible box grown to the server's 0.5° grid, so a small pan keeps the same box
    /// and needs no refetch. Nil when the view spans more than the server allows.
    struct WebcamBox: Equatable {
        let north, south, east, west: Double

        init?(_ bounds: MLNCoordinateBounds) {
            func up(_ value: Double) -> Double { (value * 2).rounded(.up) / 2 }
            func down(_ value: Double) -> Double { (value * 2).rounded(.down) / 2 }
            north = min(up(bounds.ne.latitude), 90)
            south = max(down(bounds.sw.latitude), -90)
            east = min(up(bounds.ne.longitude), 180)
            west = max(down(bounds.sw.longitude), -180)
            guard south < north, west < east, north - south <= 15, east - west <= 15 else { return nil }
        }
    }

    /// Up to 50 of the most popular webcams in view as small live pictures, refetched when the
    /// view leaves the fetched box and at most every 5 minutes otherwise. Zoomed out too far,
    /// they hide.
    func syncWebcams(style: MLNStyle, active: Bool) {
        guard active, let bounds = mapView?.visibleCoordinateBounds, let box = WebcamBox(bounds) else {
            style.removeLayers(withIdentifiers: [WeatherMapView.webcamLayerID])
            style.removeSources(withIdentifiers: [WeatherMapView.webcamSourceID])
            return
        }

        let isStale = webcamsFetchedAt.map { Date().timeIntervalSince($0) > 300 } ?? true
        if (box != webcamBox || isStale), !isLoadingWebcams {
            isLoadingWebcams = true
            // Set up front so a failed fetch backs off instead of retrying every sync.
            webcamBox = box
            webcamsFetchedAt = Date()
            Task { @MainActor [weak self] in
                defer { self?.isLoadingWebcams = false }
                do {
                    let webcams = try await APIClient.shared.getWebcams(
                        north: box.north, south: box.south, east: box.east, west: box.west)
                    let photos = await Self.webcamPhotos(webcams)
                    guard let self, !self.isTornDown else { return }
                    let markers = photos.mapValues(MapChip.webcam)
                    let gone = self.webcamMarkers.keys.filter { markers[$0] == nil }
                    self.webcams = webcams.filter { markers[$0.id] != nil }
                    self.webcamMarkers = markers
                    guard let style = self.mapView?.style else { return }
                    for id in gone {
                        style.removeImage(forName: Self.webcamImageName(id))
                    }
                    guard let source = style.source(withIdentifier: WeatherMapView.webcamSourceID) as? MLNShapeSource else { return }
                    self.registerWebcamMarkers(in: style)
                    source.shape = Self.webcamShape(self.webcams)
                } catch {
                    weatherMapLogger.error("Webcam fetch failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        guard style.source(withIdentifier: WeatherMapView.webcamSourceID) == nil else { return }
        registerWebcamMarkers(in: style)
        let source = MLNShapeSource(identifier: WeatherMapView.webcamSourceID, shape: Self.webcamShape(webcams))
        style.addSource(source)
        let layer = MLNSymbolStyleLayer(identifier: WeatherMapView.webcamLayerID, source: source)
        layer.iconImageName = NSExpression(forKeyPath: "icon")
        // Overlapping pictures hide the less popular ones (the server sorts by popularity).
        layer.symbolSortKey = NSExpression(forKeyPath: "rank")
        layer.iconAllowsOverlap = NSExpression(forConstantValue: false)
        style.addLayer(layer)
    }

    private func registerWebcamMarkers(in style: MLNStyle) {
        for (id, marker) in webcamMarkers {
            style.setImage(marker, forName: Self.webcamImageName(id))
        }
    }

    private static func webcamImageName(_ id: Int) -> String { "oscar-webcam-\(id)" }

    private static func webcamShape(_ webcams: [Components.Schemas.Webcam]) -> MLNShape {
        MLNShapeCollectionFeature(shapes: webcams.enumerated().map { rank, webcam in
            let feature = MLNPointFeature()
            feature.coordinate = CLLocationCoordinate2D(latitude: webcam.latitude, longitude: webcam.longitude)
            feature.attributes = ["webcam_id": webcam.id, "icon": webcamImageName(webcam.id), "rank": rank]
            return feature
        })
    }

    /// Each webcam's latest thumbnail. Revalidated, since Windy keeps the URL while the picture changes.
    /// Webcams whose picture fails to load are left out.
    nonisolated private static func webcamPhotos(_ webcams: [Components.Schemas.Webcam]) async -> [Int: UIImage] {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for webcam in webcams {
                group.addTask {
                    guard let url = URL(string: webcam.thumbnail_url) else { return (webcam.id, nil) }
                    let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData)
                    let data = try? await URLSession.shared.data(for: request).0
                    return (webcam.id, data.flatMap(UIImage.init(data:)))
                }
            }
            var photos: [Int: UIImage] = [:]
            for await (id, photo) in group {
                photos[id] = photo
            }
            return photos
        }
    }
}
