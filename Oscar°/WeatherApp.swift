//
//  WeatherApp.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.
//

import CoreLocation
import SwiftUI
import OSLog
import Sentry
import SentrySwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "Notifications")
    nonisolated(unsafe) private var memoryWarningObserver: NSObjectProtocol?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                ModelGridLayerState.purgeDecodedCaches()
                OscarRadarState.purgeDecodedGrids()
                RadarCustomStyleLayer.purgeCachedTextures()
                await WindFieldCache.shared.evict(retaining: [])
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        logger.info("Lifecycle: UIApplication didRegisterForRemoteNotificationsWithDeviceToken; tokenBytes=\(deviceToken.count, privacy: .public)")
        Task { @MainActor in
            NotificationSettingsManager.shared.didRegisterForRemoteNotifications(deviceToken)
        }
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("Lifecycle: UIApplication didFailToRegisterForRemoteNotificationsWithError=\(error.localizedDescription, privacy: .public)")
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }
}

@main
struct WeatherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Increase shared URLCache so aggressive tile preloading survives across frames.
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,   // 50 MB
            diskCapacity: 500 * 1024 * 1024      // 500 MB
        )

        // Screenshot runs (fastlane snapshot) swap the network layer for a fixture
        // server and skip crash reporting; a no-op in every normal launch.
        if ScreenshotMode.bootstrap() {
            // Pin the GPS-backed location to the fixture city: the simulator
            // has no fix, so views reading `location` (map camera) would sit
            // on the Location() default until a refresh lands — or forever.
            location.coordinates = CLLocationCoordinate2D(
                latitude: ScreenshotFixtures.latitude,
                longitude: ScreenshotFixtures.longitude
            )
            location.name = "Leipzig"
            return
        }

        SentrySDK.start { options in
            options.dsn = "https://f6b7fe82cd8cd8bb11dc0dc38db42255@o4507143648772096.ingest.de.sentry.io/4507143650148432"
            options.debug = false
            options.tracesSampleRate = 0.5

            options.attachScreenshot = true
            options.attachViewHierarchy = true
            options.enableMetricKit = true
            options.enableTimeToFullDisplayTracing = true
            options.swiftAsyncStacktraces = true
        }

        // Honor the user's launch default (a saved city or "current location")
        // before hydration compares coordinates and before the first refresh
        // resolves a location.
        locationService.city.applyDefaultSelectionOnLaunch()
        hydrateFromCache()
    }
    
    @State private var weather = Weather()
    @State private var location = Location()
    private let locationService = LocationService.shared
    private let persistenceController = PersistenceController.shared
    private let notificationSettingsManager = NotificationSettingsManager.shared
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if ScreenshotMode.scene == .widgets {
                    ScreenshotWidgetGallery()
                } else {
                    RootTabView()
                    OnboardingGate()
                }
            }
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(weather)
                .environment(location)
                .preferredColorScheme(.dark)
                .task {
                    // Second chance for the init-time hydration: a prewarmed
                    // launch can run `init` before first unlock, while the
                    // app-group snapshot is still data-protected and unreadable.
                    // The UI appearing means the device is unlocked, so retry;
                    // a guarded no-op whenever init already hydrated.
                    hydrateFromCache()
                    await weather.refresh(location: location)
                    await notificationSettingsManager.configureOnLaunch()
                    await WidgetBasemapRenderer.refreshIfNeeded()
                }
                .sentryTrace("RootTabView")
        }
    }

    /// Bridges the launch gap with the last session's weather so the sim opens
    /// on a real scene instead of the twilight fallback. Called from `init` and
    /// deliberately synchronous: `.task` fires only after SwiftUI commits the
    /// first frame, so the previous async hydrate let twilight flash on every
    /// cold start until its load landed — the snapshot has to be in place
    /// before the first body evaluation. The snapshot is applied when it
    /// plausibly belongs to the location the first refresh is about to query:
    /// near the saved city / last GPS fix, or — with no fix yet this early in
    /// the process — unconditionally, since the refresh that follows corrects
    /// any actual move and twilight is wrong everywhere.
    private func hydrateFromCache() {
        // Screenshot runs stay on fixture data only.
        guard !ScreenshotMode.active, weather.lastUpdated == nil else { return }
        guard let snapshot = WeatherSnapshotStore.load() else { return }
        locationService.update()
        if let current = locationService.knownCoordinates(),
           !WeatherSnapshotStore.coordinatesMatch(snapshot: snapshot.coordinates, current: current) {
            return
        }
        weather.apply(snapshot: snapshot, location: location)
    }
}
