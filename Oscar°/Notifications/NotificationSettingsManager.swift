//
//  NotificationSettingsManager.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.04.26.
//

import ActivityKit
import Foundation
import OSLog
import OpenAPIRuntime
import OpenAPIURLSession
import SwiftUI
import UIKit
import UserNotifications

let notificationLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "Notifications")

@MainActor
@Observable
final class NotificationSettingsManager: NSObject {
    static let shared = NotificationSettingsManager()

    private(set) var enabled: Bool
    private(set) var rainAlertsEnabled: Bool
    private(set) var weatherAlertsEnabled: Bool
    private(set) var liveRainStatusEnabled: Bool
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let baseURL = URL(string: radarBaseURL)!
    let keychain = KeychainStore(service: (Bundle.main.bundleIdentifier ?? "Oscar") + ".notifications")
    /// Generated client for the subscription endpoints. Deliberately NO retry
    /// middleware (registers/patches were never retried; a blind retry could
    /// double-register), and the bearer key is injected per request from the
    /// Keychain — register runs before one exists and simply goes out bare.
    @ObservationIgnored lazy var oscarNotifications: Client = Client(
        serverURL: baseURL,
        transport: URLSessionTransport(),
        middlewares: APIClient.stagingMiddlewares + [
            ContactIdentityMiddleware(),
            BearerAuthMiddleware { [keychain, subscriptionApiKey = apiKeyKey] in
                keychain.load(key: subscriptionApiKey)
            },
        ]
    )
    let locationService = LocationService.shared

    let rainAlertsEnabledKey = "notificationRainAlertsEnabled"
    let weatherAlertsEnabledKey = "notificationWeatherAlertsEnabled"
    let liveRainStatusEnabledKey = "notificationLiveRainStatusEnabled"
    let cachedDeviceTokenKey = "rainAlertDeviceToken"
    let lastSentDeviceTokenKey = "rainAlertLastSentDeviceToken"
    let subscriptionKey = "rainAlertSubscriptionId"
    let apiKeyKey = "rainAlertApiKey"
    let lastSentAPNsEnvironmentKey = "notificationLastSentAPNsEnvironment"
    let lastSentStateKey = "notificationLastSentState"
    let installationRegistrationCompletedKey = "notificationInstallationRegistrationCompleted"
    let pendingLiveActivityPushToStartTokenKey = "notificationPendingLiveActivityPushToStartToken"
    let latestLiveActivityPushToStartTokenKey = "notificationLatestLiveActivityPushToStartToken"
    let legacyDeregistrationCompletedKey = "notificationDidDeregisterLegacyRadarSubscription"
    @ObservationIgnored private var subscriptionSyncTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSyncRequested = false
    @ObservationIgnored private var pendingSyncForceRegister = false

    private override init() {
        let defaults = UserDefaults.standard
        let storedRainAlertsEnabled = defaults.bool(forKey: rainAlertsEnabledKey)
        let storedWeatherAlertsEnabled = defaults.bool(forKey: weatherAlertsEnabledKey)

        rainAlertsEnabled = storedRainAlertsEnabled
        weatherAlertsEnabled = storedWeatherAlertsEnabled
        liveRainStatusEnabled = false
        enabled = storedRainAlertsEnabled || storedWeatherAlertsEnabled
        super.init()
    }

    func configureOnLaunch() async {
        UNUserNotificationCenter.current().delegate = self
        notificationLogger.info("Lifecycle: configureOnLaunch started; enabled=\(self.enabled, privacy: .public) storedCredentials=\(self.hasStoredSubscriptionCredentials, privacy: .public)")

        // Migration: drop this device's subscription on the legacy radar.oscars.love server before
        // anything re-registers against the new server and overwrites the stored credentials.
        deregisterLegacyRadarSubscriptionIfNeeded()

        await refreshAuthorizationStatus()

        if hasNotificationAuthorization && (enabled || hasStoredSubscriptionCredentials) {
            notificationLogger.info("Lifecycle: launch prerequisites satisfied; registering for remote notifications")
            UIApplication.shared.registerForRemoteNotifications()
        } else {
            notificationLogger.info("Lifecycle: launch skipped APNs registration; authorization=\(self.authorizationStatus.debugName, privacy: .public) enabled=\(self.enabled, privacy: .public) storedCredentials=\(self.hasStoredSubscriptionCredentials, privacy: .public)")
        }

        // Live rain status rides on the rain-alert subscription — it can't be on alone.
        let storedLiveRainStatus = UserDefaults.standard.bool(forKey: liveRainStatusEnabledKey)
        setLiveRainStatusEnabledLocally(storedLiveRainStatus && rainAlertsEnabled)
        if liveRainStatusEnabled {
            RainRadarLiveActivityManager.shared.startMonitoring()
        }
    }

    func setRainAlertsEnabled(_ enabled: Bool) async -> Bool {
        notificationLogger.info("Lifecycle: setRainAlertsEnabled requested -> \(enabled, privacy: .public)")
        if enabled {
            let granted = hasNotificationAuthorization ? true : await requestNotificationPermission()
            await refreshAuthorizationStatus()
            guard granted || hasNotificationAuthorization else {
                notificationLogger.info("Lifecycle: rain alerts enable rejected; authorization=\(self.authorizationStatus.debugName, privacy: .public)")
                setRainAlertsEnabledLocally(false)
                refreshEnabledState()
                return false
            }

            setRainAlertsEnabledLocally(true)
            refreshEnabledState()
            notificationLogger.info("Lifecycle: rain alerts enabled locally; registerForRemoteNotifications")
            UIApplication.shared.registerForRemoteNotifications()
            return true
        }

        setRainAlertsEnabledLocally(false)
        setLiveRainStatusEnabledLocally(false)
        refreshEnabledState()
        notificationLogger.info("Lifecycle: rain alerts disabled locally; syncing subscription")
        await syncSubscriptionForCurrentState(forceRegister: false)
        return true
    }

    func setWeatherAlertsEnabled(_ enabled: Bool) async -> Bool {
        notificationLogger.info("Lifecycle: setWeatherAlertsEnabled requested -> \(enabled, privacy: .public)")
        if enabled {
            let granted = hasNotificationAuthorization ? true : await requestNotificationPermission()
            await refreshAuthorizationStatus()
            guard granted || hasNotificationAuthorization else {
                notificationLogger.info("Lifecycle: weather alerts enable rejected; authorization=\(self.authorizationStatus.debugName, privacy: .public)")
                setWeatherAlertsEnabledLocally(false)
                refreshEnabledState()
                return false
            }

            setWeatherAlertsEnabledLocally(true)
            refreshEnabledState()
            notificationLogger.info("Lifecycle: weather alerts enabled locally; registerForRemoteNotifications")
            UIApplication.shared.registerForRemoteNotifications()
            return true
        }

        setWeatherAlertsEnabledLocally(false)
        refreshEnabledState()
        notificationLogger.info("Lifecycle: weather alerts disabled locally; syncing subscription")
        await syncSubscriptionForCurrentState(forceRegister: false)
        return true
    }

    func setLiveRainStatusEnabled(_ enabled: Bool) async -> Bool {
        notificationLogger.info("Lifecycle: setLiveRainStatusEnabled requested -> \(enabled, privacy: .public)")
        if enabled {
            guard rainAlertsEnabled else {
                notificationLogger.info("Lifecycle: live rain status enable rejected; rain alerts disabled")
                setLiveRainStatusEnabledLocally(false)
                return false
            }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                notificationLogger.info("Lifecycle: live rain status enable rejected; Live Activities disabled in system settings")
                setLiveRainStatusEnabledLocally(false)
                return false
            }
            setLiveRainStatusEnabledLocally(true)
            RainRadarLiveActivityManager.shared.startMonitoring()
            await syncSubscriptionForCurrentState(forceRegister: false)
            await flushPendingLiveActivityTokens()
            return true
        }

        setLiveRainStatusEnabledLocally(false)
        await syncSubscriptionForCurrentState(forceRegister: false)
        return true
    }

    func didRegisterForRemoteNotifications(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        keychain.save(key: cachedDeviceTokenKey, value: token)
        let apnsEnvironment = APNsEnvironment.current()
        notificationLogger.info("Lifecycle: didRegisterForRemoteNotifications succeeded; tokenLength=\(token.count, privacy: .public) apnsEnvironment=\(apnsEnvironment.rawValue, privacy: .public) enabled=\(self.enabled, privacy: .public) storedCredentials=\(self.hasStoredSubscriptionCredentials, privacy: .public)")

        guard enabled || hasStoredSubscriptionCredentials else {
            notificationLogger.info("Lifecycle: APNs token cached without subscription sync; notifications disabled and no stored credentials")
            return
        }
        Task {
            await reconcileSubscriptionStateAfterPushRegistration()
        }
    }

    func syncLocationUpdate() async {
        guard enabled else {
            notificationLogger.info("Lifecycle: location sync skipped; notifications disabled")
            return
        }
        notificationLogger.info("Lifecycle: location changed; syncing subscription")
        await syncSubscriptionForCurrentState(forceRegister: false)
    }

    func reloadNotificationStatus() async {
        notificationLogger.info("Lifecycle: reloadNotificationStatus requested")
        await refreshAuthorizationStatus()
    }

    /// Debug-menu path: raises the bare system prompt without enabling any
    /// alert type, so the permission dance can be exercised in isolation.
    func requestPermissionOnly() async {
        _ = await requestNotificationPermission()
        await refreshAuthorizationStatus()
    }

    private var hasNotificationAuthorization: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    var hasStoredSubscriptionCredentials: Bool {
        keychain.load(key: subscriptionKey) != nil && keychain.load(key: apiKeyKey) != nil
    }

    private func setRainAlertsEnabledLocally(_ enabled: Bool) {
        rainAlertsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: rainAlertsEnabledKey)
    }

    private func setWeatherAlertsEnabledLocally(_ enabled: Bool) {
        weatherAlertsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: weatherAlertsEnabledKey)
    }

    func setLiveRainStatusEnabledLocally(_ enabled: Bool) {
        liveRainStatusEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: liveRainStatusEnabledKey)
    }

    private func refreshEnabledState() {
        enabled = rainAlertsEnabled || weatherAlertsEnabled
    }

    func notificationSettingsPayload() -> [String: any Sendable] {
        [
            "rainAlertsEnabled": rainAlertsEnabled,
            "weatherAlertsEnabled": weatherAlertsEnabled,
            "liveActivityEnabled": liveRainStatusEnabled,
        ]
    }

    private func requestNotificationPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            notificationLogger.info("Lifecycle: requestAuthorization started")
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    notificationLogger.error("Lifecycle: requestAuthorization failed; error=\(error.localizedDescription, privacy: .public)")
                } else {
                    notificationLogger.info("Lifecycle: requestAuthorization completed; granted=\(granted, privacy: .public)")
                }
                continuation.resume(returning: granted)
            }
        }
    }

    private func refreshAuthorizationStatus() async {
        let updatedStatus = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
        authorizationStatus = updatedStatus
        notificationLogger.info("Lifecycle: authorization status refreshed -> \(updatedStatus.debugName, privacy: .public)")
    }

    private func reconcileSubscriptionStateAfterPushRegistration() async {
        await syncSubscriptionForCurrentState(forceRegister: false)
    }

    private func syncSubscriptionForCurrentState(forceRegister: Bool) async {
        // A running sync folds this request into one more pass instead of racing
        // it: two concurrent registrations would create two subscriptions.
        if let subscriptionSyncTask {
            pendingSyncRequested = true
            pendingSyncForceRegister = pendingSyncForceRegister || forceRegister
            await subscriptionSyncTask.value
            return
        }

        let task = Task { @MainActor [self] in
            var force = forceRegister
            repeat {
                pendingSyncRequested = false
                await performSubscriptionSync(forceRegister: force)
                force = pendingSyncForceRegister
                pendingSyncForceRegister = false
            } while pendingSyncRequested
            subscriptionSyncTask = nil
        }
        subscriptionSyncTask = task
        await task.value
    }
}
