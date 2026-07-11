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

    // Screenshot runs preselect a page via `-watchPage <0-3>` (argument
    // domain); interactive launches start at 0 as before.
    @State private var selection = min(3, max(0, UserDefaults.standard.integer(forKey: "watchPage")))

    var body: some View {
        TabView(selection: $selection) {
            WatchNowView()
                .containerBackground(for: .tabView) {
                    WatchSimulationView()
                }
                .tag(0)

            // nil means the server confirmed there is no radar coverage here —
            // the page would have nothing to say.
            if weather.precipSeries != nil {
                WatchRainView()
                    .containerBackground(for: .tabView) {
                        WatchSimulationView(style: .gradientOnly)
                    }
                    .tag(1)
            }

            WatchHourlyView()
                .containerBackground(for: .tabView) {
                    WatchSimulationView(style: .gradientOnly)
                }
                .tag(2)

            WatchDailyView()
                .containerBackground(for: .tabView) {
                    WatchSimulationView(style: .gradientOnly)
                }
                .tag(3)
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
