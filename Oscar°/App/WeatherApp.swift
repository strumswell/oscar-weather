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
    nonisolated(unsafe) private var purgeObservers: [NSObjectProtocol] = []

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        for name in [UIApplication.didReceiveMemoryWarningNotification, UIApplication.didEnterBackgroundNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { await Self.purgeCaches() }
            }
            purgeObservers.append(observer)
        }
        let unlockObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { _ = AppLaunch.startIfReady() }
        }
        purgeObservers.append(unlockObserver)
        MainActor.assumeIsolated {
            AppLaunch.didFinishLaunching = true
            AppLaunch.startAppServicesIfReady()
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

    @MainActor
    private static func purgeCaches() async {
        ModelGridLayerState.purgeDecodedCaches()
        OscarRadarState.purgeDecodedGrids()
        CloudLayerState.purgeDecodedCaches()
        RadarCustomStyleLayer.purgeCachedTextures()
        await WindFieldCache.shared.evict(retaining: [])
        await CacheStore.shared.dropMemory()
        await ClimateArchiveStore.shared.dropMemory()
        await DailyEnsembleForecastCache.shared.dropMemory()
    }

    deinit {
        for observer in purgeObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

@MainActor
enum AppLaunch {
    static var didFinishLaunching = false
    private static var started = false
    private static var servicesStarted = false
    private static var notedLoadError = false
    private static let loadErrorURL = URL.cachesDirectory.appending(path: "store-load-error.txt")

    @discardableResult
    static func startIfReady() -> Bool {
        if started { return true }
        if ScreenshotMode.active {
            started = true
            startAppServicesIfReady()
            return true
        }
        let persistence = PersistenceController.shared
        let loaded = persistence.load()
        if !loaded, !notedLoadError, let note = PersistenceController.loadErrorNote {
            notedLoadError = true
            let text = "\(note)\n\(Date.now) uptime \(ProcessInfo.processInfo.systemUptime)"
            try? Data(text.utf8).write(to: loadErrorURL, options: .noFileProtection)
        }
        if loaded || persistence.isFileReadable {
            if CrashReporting.isEnabled {
                CrashReporting.start()
            }
            if SentrySDK.isEnabled, let note = try? String(contentsOf: loadErrorURL, encoding: .utf8) {
                SentrySDK.capture(message: "Persistent store load failed: \(note.prefix { $0 != "\n" })") { scope in
                    scope.setContext(value: ["note": note], key: "store")
                }
                try? FileManager.default.removeItem(at: loadErrorURL)
            }
        }
        guard loaded else { return false }
        started = true
        UsageCountingMiddleware.onRequest = { host in
            Task { @MainActor in
                UsageStatsStore.shared.record { $0.apiCalls[host, default: 0] += 1 }
            }
        }
        LocationService.shared.city.applyDefaultSelectionOnLaunch()
        UnitSync.shared.start()
        startAppServicesIfReady()
        return true
    }

    static func startAppServicesIfReady() {
        guard started, didFinishLaunching, !servicesStarted else { return }
        servicesStarted = true
        UNUserNotificationCenter.current().delegate = NotificationSettingsManager.shared
        RainRadarLiveActivityManager.shared.startMonitoring()
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

        if AppLaunch.startIfReady() {
            hydrateFromCache()
        }
    }
    
    @State private var weather = Weather()
    @State private var location = Location()
    @State private var isReady = false
    
    var body: some Scene {
        WindowGroup {
            if isReady || AppLaunch.startIfReady() {
                content
            } else {
                WeatherSimulationView(isOffTab: false)
                    .ignoresSafeArea()
                    .environment(weather)
                    .environment(location)
                    .preferredColorScheme(.dark)
                    .task {
                        while !AppLaunch.startIfReady() {
                            guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
                        }
                        isReady = true
                    }
            }
        }
        .commands { OscarCommands() }
    }

    private var content: some View {
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
            .environment(weather)
            .environment(location)
            .preferredColorScheme(.dark)
            .task {
                if scenePhase == .active { UsageStatsStore.shared.sceneDidActivate() }
                #if DEBUG
                await ScreenshotMode.stageOnAppear()
                #endif
                hydrateFromCache()
                await weather.refresh(location: location)
                await NotificationSettingsManager.shared.configureOnLaunch()
                await WidgetBasemapRenderer.refreshIfNeeded()
            }
            .task {
                await TestFlightMembership.stampIfNeeded()
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
                Task { await NotificationSettingsManager.shared.handleForeground() }
            }
            .sentryTrace("RootTabView")
    }

    private func hydrateFromCache() {
        guard !ScreenshotMode.active, weather.lastUpdated == nil else { return }
        guard let snapshot = WeatherSnapshotStore.load() else { return }
        let locationService = LocationService.shared
        locationService.update()
        if let current = locationService.knownCoordinates(),
           !WeatherSnapshotStore.coordinatesMatch(snapshot: snapshot.coordinates, current: current) {
            return
        }
        weather.apply(snapshot: snapshot, location: location)
    }
}
