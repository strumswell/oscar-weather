import SwiftUI
import MapKit
import WidgetKit

struct GlobalRadarEntry: TimelineEntry {
    let date: Date
    let image: UIImage
}

struct GlobalRadarProvider: TimelineProvider {
    let locationService = LocationService.shared

    init() {
        locationService.update()
    }
    
    func placeholder(in context: Context) -> GlobalRadarEntry {
        GlobalRadarEntry(date: Date(), image: UIImage(systemName: "map")!)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlobalRadarEntry) -> Void) {
        generateMapSnapshot { entry in
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlobalRadarEntry>) -> Void) {
        generateMapSnapshot { entry in
            let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries:[entry], policy: .after(nextUpdateDate))
            completion(timeline)
        }
    }

    private func generateMapSnapshot(completion: @escaping (GlobalRadarEntry) -> Void) {
        locationService.update()
        let coordinate = locationService.getCoordinates()
        
        let zoomLevel = 14
        // https://gis.stackexchange.com/questions/7430/what-ratio-scales-do-google-maps-zoom-levels-correspond-to
        let meters = 591657550.500000 / pow(2, Double(zoomLevel))

        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters)

        captureMapSnapshot(at: coordinate, region: region) { snapshotImage in
            guard let snapshot = snapshotImage else {
                let errorEntry = GlobalRadarEntry(date: Date(), image: UIImage(systemName: "exclamationmark.triangle")!)
                completion(errorEntry)
                return
            }

            let tiles = tilesCoveringRegion(region: region, zoomLevel: zoomLevel)
            overlayTiles(on: snapshot, tiles: tiles, zoomLevel: zoomLevel) { overlaidImage in
                let entry = GlobalRadarEntry(date: Date(), image: overlaidImage)
                completion(entry)
            }
        }
    }

    private func captureMapSnapshot(at coordinate: CLLocationCoordinate2D, region: MKCoordinateRegion, completion: @escaping (UIImage?) -> Void) {
        let mapSnapshotOptions = MKMapSnapshotter.Options()
        mapSnapshotOptions.region = region
        mapSnapshotOptions.size = CGSize(width: 300, height: 300)
        mapSnapshotOptions.scale = UIScreen.main.scale
        mapSnapshotOptions.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        let snapshotter = MKMapSnapshotter(options: mapSnapshotOptions)
        snapshotter.start { snapshot, error in
            guard let snapshot = snapshot, error == nil else {
                completion(nil)
                return
            }
            completion(snapshot.image)
        }
    }

    private func tilesCoveringRegion(region: MKCoordinateRegion, zoomLevel: Int) -> [(x: Int, y: Int)] {
        func tileCoords(for coordinate: CLLocationCoordinate2D, zoomLevel: Int) -> (x: Int, y: Int) {
            let x = Int(floor((coordinate.longitude + 180.0) / 360.0 * pow(2.0, Double(zoomLevel))))
            let y = Int(floor((1.0 - log(tan(coordinate.latitude * .pi / 180.0) + 1.0 / cos(coordinate.latitude * .pi / 180.0)) / .pi) / 2.0 * pow(2.0, Double(zoomLevel))))
            return (x, y)
        }

        let topLeft = CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                             longitude: region.center.longitude - region.span.longitudeDelta / 2)
        let bottomRight = CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                                 longitude: region.center.longitude + region.span.longitudeDelta / 2)

        let topLeftTile = tileCoords(for: topLeft, zoomLevel: zoomLevel)
        let bottomRightTile = tileCoords(for: bottomRight, zoomLevel: zoomLevel)

        var tiles = [(Int, Int)]()
        for x in topLeftTile.x...bottomRightTile.x {
            for y in topLeftTile.y...bottomRightTile.y {
                tiles.append((x, y))
            }
        }
        return tiles
    }

    private func overlayTiles(on snapshot: UIImage, tiles: [(x: Int, y: Int)], zoomLevel: Int, completion: @escaping (UIImage) -> Void) {
        let group = DispatchGroup()
        var tileImages = [(image: UIImage, x: Int, y: Int)]()

        let minX = tiles.min(by: { $0.x < $1.x })!.x
        let maxX = tiles.max(by: { $0.x < $1.x })!.x
        let minY = tiles.min(by: { $0.y < $1.y })!.y
        let maxY = tiles.max(by: { $0.y < $1.y })!.y

        let totalXtiles = maxX - minX + 1
        let totalYtiles = maxY - minY + 1

        let tileWidth = snapshot.size.width / CGFloat(totalXtiles)
        let tileHeight = snapshot.size.height / CGFloat(totalYtiles)

        for (x, y) in tiles {
            group.enter()
            fetchTileImage(x: x, y: y, z: zoomLevel) { tileImage in
                if let tile = tileImage {
                    tileImages.append((tile, x, y))
                }
                group.leave()
            }
        }

        group.notify(queue: DispatchQueue.main) {
            UIGraphicsBeginImageContextWithOptions(snapshot.size, true, snapshot.scale)
            snapshot.draw(at: .zero)

            for (tile, x, y) in tileImages {
                let originX = CGFloat(x - minX) * tileWidth
                let originY = CGFloat(y - minY) * tileHeight
                tile.draw(in: CGRect(x: originX, y: originY, width: tileWidth + 0.05, height: tileHeight + 0.05), blendMode: .normal, alpha: 0.7)
            }

            let compositeImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            completion(compositeImage ?? snapshot)
        }
    }



    private func fetchTileImage(x: Int, y: Int, z: Int, completion: @escaping (UIImage?) -> Void) {
        let urlString = "https://api.tomorrow.io/v4/map/tile/\(z)/\(x)/\(y)/precipitationIntensity/now.png?apikey=XjlExJsvt4ftR9UgSXvacuTwvwEEebiQ"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil, let image = UIImage(data: data) else {
                completion(nil)
                return
            }
            completion(image)
        }
        task.resume()
    }
}
