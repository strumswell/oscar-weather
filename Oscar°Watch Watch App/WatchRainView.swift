//
//  WatchRainView.swift
//  Oscar°Watch Watch App
//

import SwiftUI

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

                GeometryReader { proxy in
                    RainBarsChart(values: RainNowcastSummary.values(bars), height: proxy.size.height, axis: .none)
                }
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
}

#Preview {
    WatchRainView()
        .environment(Weather.mock)
        .environment(Location())
        .background(.black)
}
