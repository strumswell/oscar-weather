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

    /// Up to 50 of the most popular webcams in view, refetched when the view leaves the
    /// fetched box and at most every 5 minutes otherwise. Zoomed out too far, the markers hide.
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
                    guard let self, !self.isTornDown else { return }
                    self.webcams = webcams
                    (self.mapView?.style?.source(withIdentifier: WeatherMapView.webcamSourceID) as? MLNShapeSource)?
                        .shape = Self.webcamShape(webcams)
                } catch {
                    weatherMapLogger.error("Webcam fetch failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        guard style.source(withIdentifier: WeatherMapView.webcamSourceID) == nil else { return }
        let source = MLNShapeSource(identifier: WeatherMapView.webcamSourceID, shape: Self.webcamShape(webcams))
        style.addSource(source)
        style.setImage(MapChip.pin(emoji: "📷"), forName: WeatherMapView.webcamImageName)
        let layer = MLNSymbolStyleLayer(identifier: WeatherMapView.webcamLayerID, source: source)
        layer.iconImageName = NSExpression(forConstantValue: WeatherMapView.webcamImageName)
        layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
        layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        style.addLayer(layer)
    }

    private static func webcamShape(_ webcams: [Components.Schemas.Webcam]) -> MLNShape {
        MLNShapeCollectionFeature(shapes: webcams.map { webcam in
            let feature = MLNPointFeature()
            feature.coordinate = CLLocationCoordinate2D(latitude: webcam.latitude, longitude: webcam.longitude)
            feature.attributes = ["webcam_id": webcam.id]
            return feature
        })
    }
}
