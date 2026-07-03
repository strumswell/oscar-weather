import WidgetKit
import SwiftUI
import UIKit

struct RadarEntry: TimelineEntry {
    let date: Date
    let frameDate: Date
    let image: UIImage
}

/// Timeline provider for the radar widget. The map is CPU-composited over the
/// app-prerendered basemap (see RadarSnapshotRenderer); this type only supplies
/// the location and the refresh cadence.
struct RadarProvider: TimelineProvider {

    func placeholder(in context: Context) -> RadarEntry {
        // placeholder() must never fail; a missing/renamed asset would otherwise crash the
        // widget process on every gallery/redacted render.
        let image = UIImage(named: "rain") ?? UIImage(systemName: "cloud.rain") ?? UIImage()
        return RadarEntry(date: Date(), frameDate: Date(), image: image)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (RadarEntry) -> Void) {
        let displaySize = context.displaySize
        let family = context.family
        Task {
            completion(await buildWidgetEntry(displaySize: displaySize, family: family))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<RadarEntry>) -> Void) {
        let displaySize = context.displaySize
        let family = context.family
        Task {
            let entry = await buildWidgetEntry(displaySize: displaySize, family: family)
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func buildWidgetEntry(displaySize: CGSize, family: WidgetFamily) async -> RadarEntry {
        let location = await MainActor.run { LocationService.shared.update(); return LocationService.shared.getCoordinates() }
        let renderSize = snapshotSize(for: displaySize, family: family)

        guard let rendered = await RadarSnapshotRenderer.render(center: location, size: renderSize) else {
            let fallback = UIImage(systemName: "wifi.exclamationmark") ?? UIImage()
            return RadarEntry(date: Date(), frameDate: Date(), image: fallback)
        }
        return RadarEntry(
            date: Date(),
            frameDate: rendered.frameDate ?? Date(),
            image: rendered.image
        )
    }

    /// Small logical render sizes keep the composite (and the entry image) well
    /// inside the widget memory budget; the entry view scales up with .fill. The
    /// sizes are the canonical basemap-store sizes — they key the prerendered
    /// basemap lookup, so they must not vary per device.
    private func snapshotSize(for displaySize: CGSize, family: WidgetFamily) -> CGSize {
        switch family {
        case .systemLarge:
            return WidgetBasemapStore.largeCompositeSize
        default:
            return WidgetBasemapStore.smallCompositeSize
        }
    }
}
