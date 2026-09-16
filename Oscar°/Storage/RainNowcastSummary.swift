import SwiftUI

/// One capsule of the nowcast bar chart (lock-screen widget, Live Activity, watch):
/// a 3 pt stub when dry, otherwise 4 pt plus the bar fraction of the remaining area.
struct RainNowcastBar: View {
    let value: Double
    let reference: Double
    let areaHeight: CGFloat
    let fill: AnyShapeStyle

    var body: some View {
        Capsule(style: .continuous)
            .fill(fill)
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }

    private var height: CGFloat {
        guard value > 0 else { return 3 }
        let fraction = RainNowcastSummary.barFraction(value: value, reference: reference)
        return 4 + CGFloat(fraction) * max(0, areaHeight - 4)
    }
}

/// The radar nowcast as bars plus a one-line headline, shared by the lock-screen
/// rain timeline and the watch radar page.
enum RainNowcastSummary {
    static let horizon: TimeInterval = 90 * 60
    static let maxBars = 18

    /// One radar step of slack into the past so the bar for "now" survives the
    /// 5-min cadence; everything else is the upcoming window.
    static func points(from series: PrecipSeriesResponse?, now: Date) -> [PrecipPoint] {
        guard let series else { return [] }
        return Array(series.series
            .filter { $0.timestamp > now.addingTimeInterval(-150) && $0.timestamp <= now.addingTimeInterval(horizon) }
            .sorted { $0.timestamp < $1.timestamp }
            .prefix(maxBars))
    }

    static func headline(for points: [PrecipPoint], now: Date) -> String {
        let isRainingNow = (points.first?.precipitation ?? 0) > 0

        if isRainingNow {
            if let end = points.first(where: { $0.precipitation <= 0 }) {
                let minutes = max(5, Int((end.timestamp.timeIntervalSince(now) / 60).rounded()))
                if minutes <= 60 {
                    return String(localized: "Regen · noch ~\(minutes) min")
                }
                return String(localized: "Regen bis \(SettingService.formattedTime(end.timestamp))")
            }
            let last = points.last?.timestamp ?? now
            let minutes = max(5, Int((last.timeIntervalSince(now) / 60).rounded()))
            return String(localized: "Regen · noch >\(minutes) min")
        }

        if let start = points.first(where: { $0.precipitation > 0 }) {
            return String(localized: "Regen ab \(SettingService.formattedTime(start.timestamp))")
        }
        return String(localized: "Kein Regen in Sicht")
    }

    /// Fixed floor so drizzle doesn't render like a downpour.
    static func reference(for values: [Double]) -> Double {
        max(2.0, values.max() ?? 0)
    }

    /// Square root emphasizes light rain, which is what matters at a glance.
    static func barFraction(value: Double, reference: Double) -> Double {
        guard value > 0, reference > 0 else { return 0 }
        return min(1.0, (value / reference).squareRoot())
    }
}
