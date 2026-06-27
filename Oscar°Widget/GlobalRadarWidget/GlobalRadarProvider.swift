import MapKit
import SwiftUI
import WidgetKit

struct GlobalRadarEntry: TimelineEntry {
  let date: Date
  let image: UIImage
}

struct GlobalRadarProvider: TimelineProvider {
  func placeholder(in context: Context) -> GlobalRadarEntry {
    GlobalRadarEntry(date: Date(), image: UIImage(systemName: "map") ?? UIImage())
  }

  func getSnapshot(in context: Context, completion: @escaping @Sendable (GlobalRadarEntry) -> Void) {
    generateMapSnapshot { entry in
      completion(entry)
    }
  }

  func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<GlobalRadarEntry>) -> Void)
  {
    generateMapSnapshot { entry in
      let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
      let timeline = Timeline(entries: [entry], policy: .after(nextUpdateDate))
      completion(timeline)
    }
  }

  private func generateMapSnapshot(completion: @escaping @Sendable (GlobalRadarEntry) -> Void) {
    Task {
      let coordinate = await MainActor.run {
        LocationService.shared.update()
        return LocationService.shared.getCoordinates()
      }

      let zoomLevel = 14
      // https://gis.stackexchange.com/questions/7430/what-ratio-scales-do-google-maps-zoom-levels-correspond-to
      let meters = 591657550.500000 / pow(2, Double(zoomLevel))

      let region = MKCoordinateRegion(
        center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters)

      captureMapSnapshot(at: coordinate, region: region) { snapshotImage in
        guard let snapshot = snapshotImage else {
          let errorEntry = GlobalRadarEntry(
            date: Date(), image: UIImage(systemName: "exclamationmark.triangle") ?? UIImage())
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
  }

  private func captureMapSnapshot(
    at coordinate: CLLocationCoordinate2D, region: MKCoordinateRegion,
    completion: @escaping @Sendable (UIImage?) -> Void
  ) {
    let mapSnapshotOptions = MKMapSnapshotter.Options()
    mapSnapshotOptions.region = region
    mapSnapshotOptions.size = CGSize(width: 300, height: 300)
    mapSnapshotOptions.scale = 3
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

  private func tilesCoveringRegion(region: MKCoordinateRegion, zoomLevel: Int) -> [(x: Int, y: Int)]
  {
    func tileCoords(for coordinate: CLLocationCoordinate2D, zoomLevel: Int) -> (x: Int, y: Int) {
      let x = Int(floor((coordinate.longitude + 180.0) / 360.0 * pow(2.0, Double(zoomLevel))))
      let y = Int(
        floor(
          (1.0 - log(
            tan(coordinate.latitude * .pi / 180.0) + 1.0 / cos(coordinate.latitude * .pi / 180.0))
            / .pi) / 2.0 * pow(2.0, Double(zoomLevel))))
      return (x, y)
    }

    let topLeft = CLLocationCoordinate2D(
      latitude: region.center.latitude + region.span.latitudeDelta / 2,
      longitude: region.center.longitude - region.span.longitudeDelta / 2)
    let bottomRight = CLLocationCoordinate2D(
      latitude: region.center.latitude - region.span.latitudeDelta / 2,
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

  private func overlayTiles(
    on snapshot: UIImage, tiles: [(x: Int, y: Int)], zoomLevel: Int,
    completion: @escaping @Sendable (UIImage) -> Void
  ) {
    let minX = tiles.min(by: { $0.x < $1.x })!.x
    let maxX = tiles.max(by: { $0.x < $1.x })!.x
    let minY = tiles.min(by: { $0.y < $1.y })!.y
    let maxY = tiles.max(by: { $0.y < $1.y })!.y

    let totalXtiles = maxX - minX + 1
    let totalYtiles = maxY - minY + 1

    let tileWidth = snapshot.size.width / CGFloat(totalXtiles)
    let tileHeight = snapshot.size.height / CGFloat(totalYtiles)

    Task {
      // Fetch all tiles concurrently; the `for await` loop accumulates them in this one task,
      // replacing the old DispatchGroup + captured-var append (no shared mutable state).
      let tileImages = await withTaskGroup(of: (image: UIImage, x: Int, y: Int)?.self) { taskGroup in
        for (x, y) in tiles {
          taskGroup.addTask {
            await withCheckedContinuation { continuation in
              self.fetchTileImage(x: x, y: y, z: zoomLevel) { tileImage in
                continuation.resume(returning: tileImage.map { (image: $0, x: x, y: y) })
              }
            }
          }
        }
        var collected: [(image: UIImage, x: Int, y: Int)] = []
        for await result in taskGroup {
          if let result { collected.append(result) }
        }
        return collected
      }

      let composite = await MainActor.run { () -> UIImage in
        let renderer = UIGraphicsImageRenderer(size: snapshot.size)
        return renderer.image { _ in
          snapshot.draw(at: .zero)
          for (tile, x, y) in tileImages {
            let originX = CGFloat(x - minX) * tileWidth
            let originY = CGFloat(y - minY) * tileHeight
            tile.draw(
              in: CGRect(x: originX, y: originY, width: tileWidth + 0.05, height: tileHeight + 0.05),
              blendMode: .normal, alpha: 0.7)
          }
        }
      }
      completion(composite)
    }
  }

  private func fetchTileImage(x: Int, y: Int, z: Int, completion: @escaping @Sendable (UIImage?) -> Void) {
    Task {
      do {
        let rainViewerData = try await APIClient.shared.getRainViewerMaps()

        if let mostRecentFrame = rainViewerData.radar?.past?.last {
          let host = rainViewerData.host ?? "https://tilecache.rainviewer.com"
          let path = mostRecentFrame.path ?? ""

          let urlString = "\(host)\(path)/256/\(z)/\(x)/\(y)/1/1_1.png"

          guard let url = URL(string: urlString) else {
            completion(nil)
            return
          }

          var request = URLRequest(url: url)
          request.addAPIContactIdentity()

          let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil, let image = UIImage(data: data) else {
              completion(nil)
              return
            }
            completion(image)
          }
          task.resume()
        } else {
          completion(nil)
        }
      } catch {
        print("Error fetching RainViewer data: \(error)")
        completion(nil)
      }
    }
  }
}
