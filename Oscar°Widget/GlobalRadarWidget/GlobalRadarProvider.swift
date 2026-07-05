import MapKit
import OSLog
import SwiftUI
import WidgetKit

struct GlobalRadarEntry: TimelineEntry {
  let date: Date
  let image: UIImage
}

struct GlobalRadarProvider: TimelineProvider {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "RadarWidget")

  /// ≈ zoom level 14 (591657550.5 / 2^14) — the framing the widget always used.
  private static let spanMeters = 591657550.5 / Double(1 << 14)
  private static let snapshotSize = CGSize(width: 300, height: 300)
  private static let overlayAlpha: CGFloat = 0.7

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

      let region = MKCoordinateRegion(
        center: coordinate, latitudinalMeters: Self.spanMeters, longitudinalMeters: Self.spanMeters)

      // Precip overlay from oscar-server: regional radar in coverage, GFS elsewhere.
      // Fetched alongside the basemap; a nil overlay (offline, no frames) degrades
      // to the plain map instead of an error icon.
      let overlay = await RadarSnapshotRenderer.overlayImage(
        center: coordinate, spanMeters: Self.spanMeters, size: Self.snapshotSize)

      captureMapSnapshot(at: coordinate, region: region) { snapshotImage in
        guard let snapshot = snapshotImage else {
          let errorEntry = GlobalRadarEntry(
            date: Date(), image: UIImage(systemName: "exclamationmark.triangle") ?? UIImage())
          completion(errorEntry)
          return
        }

        let composite = UIGraphicsImageRenderer(size: snapshot.size).image { _ in
          snapshot.draw(at: .zero)
          overlay?.draw(
            in: CGRect(origin: .zero, size: snapshot.size),
            blendMode: .normal, alpha: Self.overlayAlpha)
        }
        completion(GlobalRadarEntry(date: Date(), image: composite))
      }
    }
  }

  private func captureMapSnapshot(
    at coordinate: CLLocationCoordinate2D, region: MKCoordinateRegion,
    completion: @escaping @Sendable (UIImage?) -> Void
  ) {
    let mapSnapshotOptions = MKMapSnapshotter.Options()
    mapSnapshotOptions.region = region
    mapSnapshotOptions.size = Self.snapshotSize
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
}
