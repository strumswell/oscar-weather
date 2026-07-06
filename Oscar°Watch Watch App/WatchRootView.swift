//
//  WatchRootView.swift
//  Oscar°Watch Watch App
//

import SwiftUI

/// Vertical page stack in the watchOS 10+ style: Now, radar nowcast, hourly,
/// and the scrollable daily list as the last tab. The Now page carries the
/// animated simulation; the content pages get the dimmed sky gradient.
struct WatchRootView: View {
    @Environment(Weather.self) private var weather: Weather

    var body: some View {
        TabView {
            WatchNowView()
                .containerBackground(for: .tabView) {
                    WatchSimulationView()
                }

            // nil means the server confirmed there is no radar coverage here —
            // the page would have nothing to say.
            if weather.precipSeries != nil {
                WatchRainView()
                    .containerBackground(for: .tabView) {
                        WatchSimulationView(style: .gradientOnly)
                    }
            }

            WatchHourlyView()
                .containerBackground(for: .tabView) {
                    WatchSimulationView(style: .gradientOnly)
                }

            WatchDailyView()
                .containerBackground(for: .tabView) {
                    WatchSimulationView(style: .gradientOnly)
                }
        }
        .tabViewStyle(.verticalPage)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    WatchRootView()
        .environment(Weather.mock)
        .environment(Location())
}
