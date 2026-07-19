//
//  Oscar_WatchApp.swift
//  Oscar°Watch Watch App
//
//  Created by Philipp Bolte on 11.04.23.
//

import CoreLocation
import SwiftUI
import WidgetKit

@main
struct Oscar_Watch_Watch_AppApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var weather: Weather
    @State private var location: Location
    @State private var lastRefreshStart: Date?

    init() {
        // App Store screenshot staging (bin/watch-screenshots.sh): the fixture
        // server answers all data endpoints, the location pins to the fixture
        // city so neither GPS nor geocoding runs on the freshly booted sim.
        let location = Location()
        let weather = MainActor.assumeIsolated {
            let weather = Weather()
            if ScreenshotMode.bootstrap() {
                location.coordinates = CLLocationCoordinate2D(
                    latitude: ScreenshotFixtures.latitude,
                    longitude: ScreenshotFixtures.longitude
                )
                location.name = "Leipzig"
            } else if let snapshot = WeatherSnapshotStore.load() {
                // Hydrate before the first frame so a cold start opens on the
                // last session's scene instead of flashing the twilight
                // fallback until scenePhase turns active (same pattern as the
                // iOS app). The refresh() hydrate below stays as the second
                // chance for launches where this read fails.
                weather.apply(snapshot: snapshot, location: location)
            }
            return weather
        }
        _location = State(initialValue: location)
        _weather = State(initialValue: weather)
    }

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
        // Second chance for the init-time hydration (e.g. a prewarmed launch
        // where the protected snapshot file wasn't readable yet); the network
        // refresh follows. Screenshot runs skip the cache — only fixture data
        // may show.
        if !ScreenshotMode.active, !weather.hasContent, let snapshot = WeatherSnapshotStore.load() {
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
