//
//  WatchRainView.swift
//  Oscar°Watch Watch App
//

import SwiftUI

/// The radar nowcast without a map: precipitation (mm/h) for the next
/// ~90 minutes as a bar chart, with the same headline logic as the
/// lock-screen rain timeline widget.
struct WatchRainView: View {
    @Environment(Weather.self) private var weather: Weather

    private static let horizon: TimeInterval = 90 * 60
    private static let maxBars = 18

    private struct RainBar: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    var body: some View {
        let now = Date()
        let bars = Self.bars(from: weather.precipSeries, now: now)

        VStack(alignment: .leading, spacing: 4) {
            Text("Radar")
                .font(.title3.weight(.semibold))

            if bars.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "cloud.slash")
                        .foregroundStyle(.secondary)
                    Text("Keine Radardaten")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(Self.headline(for: bars, now: now))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                // Flexible height, no Spacer: a Spacer would win the layout
                // fight and squeeze the chart to zero height.
                chart(bars: bars)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 4)

                HStack {
                    Text("Jetzt")
                    Spacer()
                    if let middle = bars.dropFirst(bars.count / 2).first {
                        Text(SettingService.formattedTime(middle.date))
                        Spacer()
                    }
                    if let last = bars.last {
                        Text(SettingService.formattedTime(last.date))
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Capsule bars like the lock-screen widget — Swift Charts' BarMark gets
    /// no usable bar width on a continuous date axis, so we lay out manually.
    private func chart(bars: [RainBar]) -> some View {
        // Fixed floor so drizzle doesn't render like a downpour.
        let reference = max(2.0, bars.map(\.value).max() ?? 0)

        return GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(bars) { bar in
                    Capsule(style: .continuous)
                        .fill(
                            bar.value > 0
                                ? AnyShapeStyle(.linearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                : AnyShapeStyle(.white.opacity(0.25))
                        )
                        .frame(height: barHeight(for: bar.value, reference: reference, areaHeight: proxy.size.height))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func barHeight(for value: Double, reference: Double, areaHeight: CGFloat) -> CGFloat {
        guard value > 0 else { return 3 }
        // Square root emphasizes light rain, which is what matters at a glance.
        let fraction = min(1.0, (value / reference).squareRoot())
        return 4 + CGFloat(fraction) * max(0, areaHeight - 4)
    }

    /// One radar step of slack into the past so the bar for "now" survives
    /// the 5-min cadence; everything else is the upcoming window.
    private static func bars(from series: PrecipSeriesResponse?, now: Date) -> [RainBar] {
        guard let series else { return [] }
        return series.series
            .filter { $0.timestamp > now.addingTimeInterval(-150) && $0.timestamp <= now.addingTimeInterval(horizon) }
            .sorted { $0.timestamp < $1.timestamp }
            .prefix(maxBars)
            .map { RainBar(date: $0.timestamp, value: max(0, $0.precipitation)) }
    }

    /// Same wording as the lock-screen rain timeline widget.
    private static func headline(for bars: [RainBar], now: Date) -> String {
        let isRainingNow = (bars.first?.value ?? 0) > 0

        if isRainingNow {
            if let end = bars.first(where: { $0.value <= 0 }) {
                let minutes = max(5, Int((end.date.timeIntervalSince(now) / 60).rounded()))
                if minutes <= 60 {
                    return String(localized: "Regen · noch ~\(minutes) min")
                }
                return String(localized: "Regen bis \(SettingService.formattedTime(end.date))")
            }
            let minutes = max(5, Int((bars.last!.date.timeIntervalSince(now) / 60).rounded()))
            return String(localized: "Regen · noch >\(minutes) min")
        }

        if let start = bars.first(where: { $0.value > 0 }) {
            return String(localized: "Regen ab \(SettingService.formattedTime(start.date))")
        }
        return String(localized: "Kein Regen in Sicht")
    }
}

#Preview {
    WatchRainView()
        .environment(Weather.mock)
        .environment(Location())
        .background(.black)
}
