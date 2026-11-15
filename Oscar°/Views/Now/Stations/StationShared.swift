// Station pieces shared by the app and the widget extensions.
import SwiftUI

struct StationSparkline: View {
    let history: [Components.Schemas.StationReading]
    let unit: TemperatureUnit
    var showsExtremes = true

    var body: some View {
        let labelBand: CGFloat = showsExtremes ? 11 : 3
        Canvas { context, size in
            let points = history.compactMap { reading in
                reading.temperature_c.map { (reading.time.timeIntervalSince1970, $0) }
            }
            guard points.count > 1, let last = points.last,
                  let lowPoint = points.min(by: { $0.1 < $1.1 }), let highPoint = points.max(by: { $0.1 < $1.1 }) else { return }
            let low = lowPoint.1
            let span = max(highPoint.1 - low, 1)
            let start = points[0].0
            let duration = max(last.0 - start, 1)
            let height = size.height - 2 * labelBand
            func position(_ point: (Double, Double)) -> CGPoint {
                CGPoint(
                    x: 2 + (point.0 - start) / duration * (size.width - 5),
                    y: labelBand + (1 - (point.1 - low) / span) * height)
            }
            var line = Path()
            line.addLines(points.map(position))
            var stroke = context
            stroke.opacity = 0.85
            stroke.stroke(line, with: .foreground,
                          style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            let end = position(last)
            context.fill(Path(ellipseIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)), with: .foreground)

            guard showsExtremes, highPoint.1 > low else { return }
            for (point, isHigh) in [(highPoint, true), (lowPoint, false)] {
                let label = context.resolve(
                    Text(verbatim: unit.string(point.1))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6)))
                let labelSize = label.measure(in: size)
                let anchor = position(point)
                let labelX = min(max(anchor.x, labelSize.width / 2), size.width - labelSize.width / 2)
                context.draw(label, at: CGPoint(x: labelX, y: isHigh ? anchor.y - 2 : anchor.y + 2),
                             anchor: isHigh ? .bottom : .top)
            }
        }
        .accessibilityHidden(true)
    }
}

extension [Components.Schemas.NearbyStation] {
    func head(favorites: [String]) -> Components.Schemas.NearbyStation? {
        let reporting = filter { $0.current.temperature_c != nil }
        return reporting.first { favorites.contains($0.id) } ?? reporting.first
    }
}

func stationSubtitle(_ station: Components.Schemas.NearbyStation, timeZone: TimeZone, units: Units) -> String {
    let time = SettingService.formattedTime(station.last_report_at, timeZone: timeZone)
    return "\(units.distanceString(station.distance_km)) \(compassDirection(station.bearing_deg)) · \(time)"
}
