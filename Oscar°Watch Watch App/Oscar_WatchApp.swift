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
        let location = Location()
        let weather = MainActor.assumeIsolated {
            let weather = Weather()
            #if DEBUG
            if ScreenshotMode.bootstrap() {
                location.coordinates = CLLocationCoordinate2D(
                    latitude: ScreenshotFixtures.latitude,
                    longitude: ScreenshotFixtures.longitude
                )
                location.name = "Leipzig"
                return weather
            }
            #endif
            if let snapshot = WeatherSnapshotStore.load() {
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
        if !ScreenshotMode.active, !weather.hasContent, let snapshot = WeatherSnapshotStore.load() {
            weather.apply(snapshot: snapshot, location: location)
        }

        if let lastRefreshStart, Date.now.timeIntervalSince(lastRefreshStart) < 60 {
            return
        }
        lastRefreshStart = .now

        Task {
            await weather.refresh(location: location)
            weather.updateTime()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
