//
//  WeatherApp.swift
//  Oscar°
//
//  Created by Philipp Bolte on 22.09.20.
//

import CoreLocation
import SwiftUI
import OSLog
import UserNotifications
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
                CloudLayerState.purgeDecodedCaches()
                RadarCustomStyleLayer.purgeCachedTextures()
                await WindFieldCache.shared.evict(retaining: [])
                await CacheStore.shared.dropMemory()
                await ClimateArchiveStore.shared.dropMemory()
                await DailyEnsembleForecastCache.shared.dropMemory()
            }
        }
        MainActor.assumeIsolated {
            UNUserNotificationCenter.current().delegate = NotificationSettingsManager.shared
            RainRadarLiveActivityManager.shared.startMonitoring()
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

enum CrashReporting {
    static let enabledKey = "crashReportsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? OnboardingCoordinator.hasCompleted
    }

    static var hasAnswered: Bool {
        UserDefaults.standard.object(forKey: enabledKey) != nil
    }

    static func answer(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if enabled {
            start()
        } else {
            stop()
        }
    }

    static func start() {
        guard !SentrySDK.isEnabled else { return }
        SentrySDK.start { options in
            options.dsn = "https://f6b7fe82cd8cd8bb11dc0dc38db42255@o4507143648772096.ingest.de.sentry.io/4507143650148432"
            options.debug = false
            options.tracesSampleRate = 0.5

            options.attachScreenshot = true
            options.attachViewHierarchy = true
            options.enableMetricKit = true
            options.enableTimeToFullDisplayTracing = true
            options.swiftAsyncStacktraces = true

            options.beforeBreadcrumb = { crumb in
                crumb.data = crumb.data?.mapValues { value -> Any in
                    guard let text = value as? String else { return value }
                    return redactingAPIKey(text)
                }
                return crumb
            }
            options.beforeSendSpan = { span in
                if let query = span.data["http.query"] as? String {
                    span.setData(value: redactingAPIKey(query), key: "http.query")
                }
                return span
            }
            options.beforeSend = { event in
                event.request?.queryString = event.request?.queryString.map(redactingAPIKey)
                event.request?.url = event.request?.url.map(redactingAPIKey)
                return event
            }
        }
    }

    private static func redactingAPIKey(_ text: String) -> String {
        guard let key = OpenMeteoCustomer.apiKey else { return text }
        return text.replacingOccurrences(of: key, with: "[redacted]")
    }

    static func stop() {
        SentrySDK.close()
    }
}

@main
struct WeatherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 500 * 1024 * 1024
        )

        #if DEBUG
        if ScreenshotMode.bootstrap() {
            location.coordinates = CLLocationCoordinate2D(
                latitude: ScreenshotFixtures.latitude,
                longitude: ScreenshotFixtures.longitude
            )
            location.name = "Leipzig"
            return
        }
        #endif

        if CrashReporting.isEnabled {
            CrashReporting.start()
        }

        UsageCountingMiddleware.onRequest = { host in
            Task { @MainActor in
                UsageStatsStore.shared.record { $0.apiCalls[host, default: 0] += 1 }
            }
        }

        locationService.city.applyDefaultSelectionOnLaunch()
        hydrateFromCache()
        UnitSync.shared.start()
    }
    
    @State private var weather = Weather()
    @State private var location = Location()
    private let locationService = LocationService.shared
    private let persistenceController = PersistenceController.shared
    private let notificationSettingsManager = NotificationSettingsManager.shared
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                #if DEBUG
                if ScreenshotMode.scene == .widgets {
                    ScreenshotWidgetGallery()
                } else {
                    RootTabView()
                    OnboardingGate()
                }
                #else
                RootTabView()
                OnboardingGate()
                #endif
            }
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(weather)
                .environment(location)
                .preferredColorScheme(.dark)
                .task {
                    #if DEBUG
                    await ScreenshotMode.stageOnAppear()
                    #endif
                    hydrateFromCache()
                    await weather.refresh(location: location)
                    await notificationSettingsManager.configureOnLaunch()
                    await WidgetBasemapRenderer.refreshIfNeeded()
                }
                .task {
                    await SupporterStore.shared.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    #if DEBUG
                    ScreenshotMode.scenePhaseDidChange(phase)
                    #endif
                    if phase == .background { UsageStatsStore.shared.sceneDidEnterBackground() }
                    guard phase == .active else { return }
                    UsageStatsStore.shared.sceneDidActivate()
                    Task { await notificationSettingsManager.handleForeground() }
                }
                .sentryTrace("RootTabView")
        }
        .commands { OscarCommands() }
    }

    private func hydrateFromCache() {
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
