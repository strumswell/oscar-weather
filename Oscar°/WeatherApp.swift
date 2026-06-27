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
                OscarRadarState.purgeDecodedCaches()
                GFSImageLayerState.purgeDecodedCaches()
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
    }
    
    @State private var weather = Weather()
    @State private var location = Location()
    private let locationService = LocationService.shared
    private let persistenceController = PersistenceController.shared
    private let notificationSettingsManager = NotificationSettingsManager.shared
    
    var body: some Scene {
        WindowGroup {
            NowView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(weather)
                .environment(location)
                .preferredColorScheme(.dark)
                .task {
                    if weather.lastUpdated == nil,
                       let snapshot = WeatherSnapshotStore.load() {
                        locationService.update()
                        let current = CLLocation(
                            latitude: locationService.getCoordinates().latitude,
                            longitude: locationService.getCoordinates().longitude
                        )
                        let cached = CLLocation(
                            latitude: snapshot.coordinates.latitude,
                            longitude: snapshot.coordinates.longitude
                        )
                        if current.distance(from: cached) < 50_000 {
                            weather.apply(snapshot: snapshot, location: location)
                        }
                    }
                    await weather.refresh(location: location)
                    await notificationSettingsManager.configureOnLaunch()
                }
                .sentryTrace("NowView")
        }
    }
}
