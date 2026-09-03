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

    var body: some View {
        let now = Date()
        let bars = RainNowcastSummary.points(from: weather.precipSeries, now: now)

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
                Text(RainNowcastSummary.headline(for: bars, now: now))
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
                        Text(SettingService.formattedTime(middle.timestamp))
                        Spacer()
                    }
                    if let last = bars.last {
                        Text(SettingService.formattedTime(last.timestamp))
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Capsule bars like the lock-screen widget — Swift Charts' BarMark gets
    /// no usable bar width on a continuous date axis, so we lay out manually.
    private func chart(bars: [PrecipPoint]) -> some View {
        let reference = RainNowcastSummary.reference(for: bars.map(\.precipitation))

        return GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(bars, id: \.timestamp) { bar in
                    Capsule(style: .continuous)
                        .fill(
                            bar.precipitation > 0
                                ? AnyShapeStyle(.linearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                : AnyShapeStyle(.white.opacity(0.25))
                        )
                        .frame(height: barHeight(for: bar.precipitation, reference: reference, areaHeight: proxy.size.height))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func barHeight(for value: Double, reference: Double, areaHeight: CGFloat) -> CGFloat {
        guard value > 0 else { return 3 }
        let fraction = RainNowcastSummary.barFraction(value: value, reference: reference)
        return 4 + CGFloat(fraction) * max(0, areaHeight - 4)
    }
}

#Preview {
    WatchRainView()
        .environment(Weather.mock)
        .environment(Location())
        .background(.black)
}
