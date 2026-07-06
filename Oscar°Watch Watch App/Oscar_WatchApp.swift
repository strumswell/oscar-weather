//
//  Oscar_WatchApp.swift
//  Oscar°Watch Watch App
//
//  Created by Philipp Bolte on 11.04.23.
//

import SwiftUI
import WidgetKit

@main
struct Oscar_Watch_Watch_AppApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var weather = Weather()
    @State private var location = Location()
    @State private var lastRefreshStart: Date?

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(weather)
                .environment(location)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refresh()
        }
    }

    private func refresh() {
        // Cold start: show the cached snapshot immediately, the network refresh follows.
        if !weather.hasContent, let snapshot = WeatherSnapshotStore.load() {
            weather.apply(snapshot: snapshot, location: location)
        }

        // Wrist-raise reactivations come in bursts; one in-flight/very recent refresh is enough.
        if let lastRefreshStart, Date.now.timeIntervalSince(lastRefreshStart) < 60 {
            return
        }
        lastRefreshStart = .now

        Task {
            await weather.refresh(location: location)
            weather.updateTime()
            // Complications fetch on their own timelines; nudging them here means they
            // pick up fresh data right after the app already paid for the request.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
