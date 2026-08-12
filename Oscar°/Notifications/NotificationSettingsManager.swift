//
//  NotificationSettingsManager.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.04.26.
//

import ActivityKit
import Foundation
import HTTPTypes
import OSLog
import OpenAPIRuntime
import OpenAPIURLSession
import Security
import SwiftUI
import UIKit
import UserNotifications

private let notificationLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "Notifications")

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
    /// Generated client for the subscription endpoints. Deliberately NO retry
    /// middleware (registers/patches were never retried; a blind retry could
    /// double-register), and the bearer key is injected per request from the
    /// Keychain — register runs before one exists and simply goes out bare.
    @ObservationIgnored private lazy var oscarNotifications: Client = Client(
        serverURL: baseURL,
        transport: URLSessionTransport(),
        middlewares: APIClient.stagingMiddlewares + [
            ContactIdentityMiddleware(),
            BearerAuthMiddleware { [subscriptionApiKey = apiKeyKey] in
                Keychain.load(key: subscriptionApiKey)
            },
        ]
    )
    private let locationService = LocationService.shared

    private let rainAlertsEnabledKey = "notificationRainAlertsEnabled"
    private let weatherAlertsEnabledKey = "notificationWeatherAlertsEnabled"
    private let liveRainStatusEnabledKey = "notificationLiveRainStatusEnabled"
    private let cachedDeviceTokenKey = "rainAlertDeviceToken"
    private let lastSentDeviceTokenKey = "rainAlertLastSentDeviceToken"
    private let subscriptionKey = "rainAlertSubscriptionId"
    private let apiKeyKey = "rainAlertApiKey"
    private let lastSentAPNsEnvironmentKey = "notificationLastSentAPNsEnvironment"
    private let lastSentStateKey = "notificationLastSentState"
    private let installationRegistrationCompletedKey = "notificationInstallationRegistrationCompleted"
    private let pendingLiveActivityPushToStartTokenKey = "notificationPendingLiveActivityPushToStartToken"
    private let latestLiveActivityPushToStartTokenKey = "notificationLatestLiveActivityPushToStartToken"
    private let legacyDeregistrationCompletedKey = "notificationDidDeregisterLegacyRadarSubscription"
    @ObservationIgnored private var subscriptionSyncTask: Task<Void, Never>?

    /// Old notification backend the app used before migrating to ``radarBaseURL`` (server.oscars.love).
    /// Kept only so the client can best-effort de-register its legacy subscription once during migration.
    private let legacyRadarBaseURL = URL(string: "https://radar.oscars.love")!

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
        Keychain.save(key: cachedDeviceTokenKey, value: token)
        let apnsEnvironment = currentAPNsEnvironment()
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

    func syncTimeFormatPreferenceUpdate() async {
        notificationLogger.info("Lifecycle: time format preference changed; syncing subscription")
        await syncSubscriptionForCurrentState(forceRegister: false)
    }

    private var hasNotificationAuthorization: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    private var hasStoredSubscriptionCredentials: Bool {
        Keychain.load(key: subscriptionKey) != nil && Keychain.load(key: apiKeyKey) != nil
    }

    private func setRainAlertsEnabledLocally(_ enabled: Bool) {
        rainAlertsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: rainAlertsEnabledKey)
    }

    private func setWeatherAlertsEnabledLocally(_ enabled: Bool) {
        weatherAlertsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: weatherAlertsEnabledKey)
    }

    private func setLiveRainStatusEnabledLocally(_ enabled: Bool) {
        liveRainStatusEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: liveRainStatusEnabledKey)
    }

    private func refreshEnabledState() {
        enabled = rainAlertsEnabled || weatherAlertsEnabled
    }

    private func notificationSettingsPayload() -> [String: any Sendable] {
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
        if let subscriptionSyncTask {
            await subscriptionSyncTask.value
            if forceRegister {
                await syncSubscriptionForCurrentState(forceRegister: true)
            }
            return
        }

        let task = Task { @MainActor [self] in
            await performSubscriptionSync(forceRegister: forceRegister)
            subscriptionSyncTask = nil
        }
        subscriptionSyncTask = task
        await task.value
    }

    private func performSubscriptionSync(forceRegister: Bool) async {
        guard let token = Keychain.load(key: cachedDeviceTokenKey), !token.isEmpty else {
            notificationLogger.info("Lifecycle: subscription sync skipped; missing cached device token")
            return
        }

        let apnsEnvironment = currentAPNsEnvironment()

        notificationLogger.info("Lifecycle: subscription sync started; forceRegister=\(forceRegister, privacy: .public) apnsEnvironment=\(apnsEnvironment.rawValue, privacy: .public) enabled=\(self.enabled, privacy: .public) rainAlerts=\(self.rainAlertsEnabled, privacy: .public) weatherAlerts=\(self.weatherAlertsEnabled, privacy: .public)")

        locationService.update()
        let currentLocation = await locationService.getLocation()
        let outboundCoordinates = LocationService.outboundCoordinate(currentLocation.coordinates)
        let cityName = currentLocation.name.isEmpty ? "Current Location" : currentLocation.name

        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        let language = languageCode.lowercased().hasPrefix("de") ? "de" : "en"

        var patchBody: [String: any Sendable] = [
            "locationLat": outboundCoordinates.latitude,
            "locationLon": outboundCoordinates.longitude,
            "locationName": cityName,
            "timezone": TimeZone.current.identifier,
            "language": language,
            "timeFormat": SettingService.resolvedTimeFormatAPIValue,
            "apnsEnvironment": apnsEnvironment.rawValue,
        ]
        patchBody.merge(notificationSettingsPayload()) { _, new in new }

        var registrationBody = patchBody
        registrationBody["deviceToken"] = token

        let currentState = SentSubscriptionState(
            locationLat: outboundCoordinates.latitude,
            locationLon: outboundCoordinates.longitude,
            locationName: cityName,
            timezone: TimeZone.current.identifier,
            language: language,
            timeFormat: SettingService.resolvedTimeFormatAPIValue,
            rainAlertsEnabled: rainAlertsEnabled,
            weatherAlertsEnabled: weatherAlertsEnabled,
            liveRainStatusEnabled: liveRainStatusEnabled,
            apnsEnvironment: apnsEnvironment
        )

        let lastSentToken = Keychain.load(key: lastSentDeviceTokenKey)
        let lastSentState = loadLastSentSubscriptionState()
        let lastSentAPNsEnvironment = loadLastSentAPNsEnvironment() ?? lastSentState?.apnsEnvironment
        let registrationCompleted = UserDefaults.standard.bool(forKey: installationRegistrationCompletedKey)
        let shouldRegister = forceRegister
            || !registrationCompleted
            || Keychain.load(key: subscriptionKey) == nil
            || Keychain.load(key: apiKeyKey) == nil
            || lastSentAPNsEnvironment != apnsEnvironment
            || lastSentToken != token

        if shouldRegister {
            let reason: String
            if forceRegister {
                reason = "forced"
            } else if !registrationCompleted {
                reason = "installationRegistrationIncomplete"
            } else if Keychain.load(key: subscriptionKey) == nil || Keychain.load(key: apiKeyKey) == nil {
                reason = "missingCredentials"
            } else if lastSentAPNsEnvironment != apnsEnvironment {
                reason = "apnsEnvironmentChanged"
            } else {
                reason = "deviceTokenChanged"
            }
            notificationLogger.info("Lifecycle: subscription sync choosing register path; reason=\(reason, privacy: .public)")
            await register(body: registrationBody, token: token, state: currentState)
            return
        }

        guard lastSentState != currentState else {
            notificationLogger.info("Lifecycle: subscription sync skipped; outbound state unchanged")
            return
        }

        switch await patchSettings(patchBody, token: token, state: currentState) {
        case .success:
            notificationLogger.info("Lifecycle: subscription sync patch succeeded")
        case .notFound:
            notificationLogger.info("Lifecycle: subscription sync patch returned notFound; retrying with register")
            await register(body: registrationBody, token: token, state: currentState)
        case .failure:
            notificationLogger.error("Lifecycle: subscription sync patch failed")
        }
    }

    private func register(body: [String: any Sendable], token: String, state: SentSubscriptionState) async {
        guard let payload = try? OpenAPIObjectContainer(unvalidatedValue: body.mapValues { $0 as (any Sendable)? })
        else { return }

        notificationLogger.info("Lifecycle: subscription register request started; payload=\(self.loggablePayload(from: body), privacy: .public)")

        do {
            let output = try await oscarNotifications.registerNotifications(
                .init(body: .json(.init(additionalProperties: payload))))
            let registerResponse: Components.Schemas.NotificationRegisterResponse
            switch output {
            case .ok(let ok):
                registerResponse = try ok.body.json
            case .created(let created):
                registerResponse = try created.body.json
            case .undocumented(let statusCode, _):
                notificationLogger.error("Lifecycle: subscription register request failed; status=\(statusCode, privacy: .public)")
                return
            }
            Keychain.save(key: subscriptionKey, value: registerResponse.subscriptionId)
            Keychain.save(key: apiKeyKey, value: registerResponse.apiKey)
            Keychain.save(key: lastSentDeviceTokenKey, value: token)
            persistLastSentSubscriptionState(state)
            UserDefaults.standard.set(true, forKey: installationRegistrationCompletedKey)
            notificationLogger.info("Lifecycle: subscription register request succeeded; subscriptionIdLength=\(registerResponse.subscriptionId.count, privacy: .public)")
            // A register creates a new subscription row: a previously synced
            // push-to-start token belongs to the old one — re-send it.
            if let latest = UserDefaults.standard.string(forKey: latestLiveActivityPushToStartTokenKey) {
                UserDefaults.standard.set(latest, forKey: pendingLiveActivityPushToStartTokenKey)
                UserDefaults.standard.removeObject(forKey: latestLiveActivityPushToStartTokenKey)
            }
            await flushPendingLiveActivityTokens()
        } catch {
            notificationLogger.error("Lifecycle: subscription register request threw error=\(error.localizedDescription, privacy: .public)")
        }
    }

    /// Best-effort, one-time removal of this device's subscription from the legacy
    /// radar.oscars.love backend during the migration to server.oscars.love.
    ///
    /// This runs synchronously before any sync against the new server, so the credentials
    /// still stored in the Keychain belong to the legacy subscription. They are captured
    /// here and the actual DELETE is fired without blocking launch — a slow or offline
    /// legacy server must never delay APNs registration.
    ///
    /// It is intentionally fire-once: the completion flag is set up front so we never try
    /// again, even if the request fails. The legacy server may already be decommissioned
    /// (offline) or the device may already be gone from it (404); both are expected and
    /// handled by silently giving up. The request is hardcoded to the legacy host, so even
    /// if the stored credentials already point at the new server the call simply 404s.
    private func deregisterLegacyRadarSubscriptionIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyDeregistrationCompletedKey) else { return }

        // Fire-once: regardless of outcome (deleted, already gone, or legacy server
        // offline) we never attempt this again.
        defaults.set(true, forKey: legacyDeregistrationCompletedKey)

        guard let subscriptionId = Keychain.load(key: subscriptionKey),
              let apiKey = Keychain.load(key: apiKeyKey)
        else {
            // Nothing was ever registered (e.g. fresh install); no legacy cleanup required.
            notificationLogger.info("Lifecycle: legacy radar de-registration skipped; no stored credentials")
            return
        }

        notificationLogger.info("Lifecycle: legacy radar de-registration request started")

        // Fire-and-forget on a one-off client: the credentials are captured by value, so a
        // later re-registration overwriting the Keychain cannot affect it, and launch is
        // never blocked on the legacy host (10 s request timeout).
        let legacyBaseURL = legacyRadarBaseURL
        Task.detached {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            let legacyClient = Client(
                serverURL: legacyBaseURL,
                transport: URLSessionTransport(
                    configuration: .init(session: URLSession(configuration: configuration))),
                middlewares: [
                    ContactIdentityMiddleware(),
                    BearerAuthMiddleware { apiKey },
                ]
            )
            do {
                // 204 = deleted, 404 = already gone; any other status is ignored (best-effort).
                let output = try await legacyClient.deleteNotificationSubscription(
                    .init(path: .init(subscriptionId: subscriptionId)))
                notificationLogger.info("Lifecycle: legacy radar de-registration finished; outcome=\(String(describing: output), privacy: .public)")
            } catch {
                // Legacy server offline/unreachable — silently give up.
                notificationLogger.info("Lifecycle: legacy radar de-registration could not reach legacy server; giving up silently (\(error.localizedDescription, privacy: .public))")
            }
        }
    }

    private func patchSettings(_ body: [String: any Sendable], token: String, state: SentSubscriptionState) async -> PatchResult {
        guard let subscriptionId = Keychain.load(key: subscriptionKey),
              Keychain.load(key: apiKeyKey) != nil,
              let payload = try? OpenAPIObjectContainer(unvalidatedValue: body.mapValues { $0 as (any Sendable)? })
        else {
            return .notFound
        }

        notificationLogger.info("Lifecycle: subscription patch request started; payload=\(self.loggablePayload(from: body), privacy: .public)")

        do {
            let output = try await oscarNotifications.patchNotificationSettings(
                .init(path: .init(subscriptionId: subscriptionId), body: .json(.init(additionalProperties: payload))))
            switch output {
            case .ok, .noContent:
                Keychain.save(key: lastSentDeviceTokenKey, value: token)
                persistLastSentSubscriptionState(state)
                notificationLogger.info("Lifecycle: subscription patch request succeeded")
                await flushPendingLiveActivityTokens()
                return .success
            case .undocumented(let statusCode, _) where statusCode == 404:
                Keychain.delete(key: subscriptionKey)
                Keychain.delete(key: apiKeyKey)
                notificationLogger.info("Lifecycle: subscription patch request returned 404; cleared stored credentials")
                return .notFound
            case .undocumented(let statusCode, _):
                notificationLogger.error("Lifecycle: subscription patch request failed; status=\(statusCode, privacy: .public)")
                return .failure
            }
        } catch {
            notificationLogger.error("Lifecycle: subscription patch request threw error=\(error.localizedDescription, privacy: .public)")
            return .failure
        }
    }

    func syncLiveActivityPushToStartToken(_ token: String) async {
        guard liveRainStatusEnabled else {
            // iOS can hand out the token before the user enables the feature; keep the
            // freshest one so enabling later syncs it without waiting for a new one.
            UserDefaults.standard.set(token, forKey: pendingLiveActivityPushToStartTokenKey)
            return
        }
        guard UserDefaults.standard.string(forKey: latestLiveActivityPushToStartTokenKey) != token else {
            return
        }
        if await patchLiveActivityToken(path: "push-to-start-token", body: ["token": token]) {
            UserDefaults.standard.set(token, forKey: latestLiveActivityPushToStartTokenKey)
            UserDefaults.standard.removeObject(forKey: pendingLiveActivityPushToStartTokenKey)
        } else {
            UserDefaults.standard.set(token, forKey: pendingLiveActivityPushToStartTokenKey)
        }
    }

    func syncLiveActivityUpdateToken(activityId: String, token: String) async {
        guard liveRainStatusEnabled else { return }
        _ = await patchLiveActivityToken(
            path: "update-token",
            body: ["activityId": activityId, "token": token]
        )
    }

    private func patchLiveActivityToken(path: String, body: [String: any Sendable]) async -> Bool {
        guard let subscriptionId = Keychain.load(key: subscriptionKey),
              Keychain.load(key: apiKeyKey) != nil,
              let payload = try? OpenAPIObjectContainer(unvalidatedValue: body.mapValues { $0 as (any Sendable)? })
        else { return false }

        do {
            let output = try await oscarNotifications.patchLiveActivityToken(
                .init(path: .init(subscriptionId: subscriptionId, tokenKind: path), body: .json(.init(additionalProperties: payload))))
            switch output {
            case .ok, .noContent:
                notificationLogger.info("Lifecycle: live-activity \(path, privacy: .public) patch finished")
                return true
            case .undocumented(let statusCode, _):
                notificationLogger.info("Lifecycle: live-activity \(path, privacy: .public) patch finished; status=\(statusCode, privacy: .public)")
                return false
            }
        } catch {
            notificationLogger.error("Lifecycle: live-activity \(path, privacy: .public) patch threw error=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Re-sends a push-to-start token that arrived while the feature was off or a
    /// prior sync failed. Called after enabling and after successful register/patch.
    private func flushPendingLiveActivityTokens() async {
        guard liveRainStatusEnabled,
              let pending = UserDefaults.standard.string(forKey: pendingLiveActivityPushToStartTokenKey)
        else { return }
        await syncLiveActivityPushToStartToken(pending)
    }

    private enum PatchResult {
        case success
        case notFound
        case failure
    }

    private struct SentSubscriptionState: Codable, Equatable {
        let locationLat: Double
        let locationLon: Double
        let locationName: String
        let timezone: String
        let language: String
        let timeFormat: String
        let rainAlertsEnabled: Bool
        let weatherAlertsEnabled: Bool
        let liveRainStatusEnabled: Bool
        let apnsEnvironment: APNsEnvironment
    }

    private enum APNsEnvironment: String, Codable {
        case sandbox
        case production
    }

    private func currentAPNsEnvironment() -> APNsEnvironment {
        if let provisionPath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
           let profile = try? String(contentsOfFile: provisionPath, encoding: .isoLatin1),
           let entitlementRange = profile.range(of: "<key>aps-environment</key>"),
           let stringStartRange = profile.range(of: "<string>", range: entitlementRange.upperBound..<profile.endIndex),
           let stringEndRange = profile.range(of: "</string>", range: stringStartRange.upperBound..<profile.endIndex) {
            let entitlementValue = profile[stringStartRange.upperBound..<stringEndRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            switch entitlementValue.lowercased() {
            case "development":
                return .sandbox
            case "production":
                return .production
            default:
                break
            }
        }

        return .production
    }

    private func loadLastSentSubscriptionState() -> SentSubscriptionState? {
        guard let data = UserDefaults.standard.data(forKey: lastSentStateKey) else {
            return nil
        }

        return try? JSONDecoder().decode(SentSubscriptionState.self, from: data)
    }

    private func loadLastSentAPNsEnvironment() -> APNsEnvironment? {
        guard let rawValue = UserDefaults.standard.string(forKey: lastSentAPNsEnvironmentKey) else {
            return nil
        }

        return APNsEnvironment(rawValue: rawValue)
    }

    private func persistLastSentSubscriptionState(_ state: SentSubscriptionState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }

        UserDefaults.standard.set(data, forKey: lastSentStateKey)
        UserDefaults.standard.set(state.apnsEnvironment.rawValue, forKey: lastSentAPNsEnvironmentKey)
    }

    private func loggablePayload(from body: [String: any Sendable]) -> String {
        var sanitizedBody = body
        if let deviceToken = sanitizedBody["deviceToken"] as? String {
            sanitizedBody["deviceToken"] = redactedDeviceToken(deviceToken)
        }

        guard JSONSerialization.isValidJSONObject(sanitizedBody),
              let data = try? JSONSerialization.data(withJSONObject: sanitizedBody, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else {
            return String(describing: sanitizedBody)
        }

        return json
    }

    private func redactedDeviceToken(_ token: String) -> String {
        guard token.count > 12 else { return "<redacted len=\(token.count)>" }
        let prefix = token.prefix(8)
        let suffix = token.suffix(4)
        return "\(prefix)...\(suffix) (len=\(token.count))"
    }

    private enum Keychain {
        static func save(key: String, value: String) {
            guard let data = value.data(using: .utf8) else { return }

            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
            ]

            SecItemDelete(query as CFDictionary)

            let attributes: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecValueData as String: data,
            ]

            SecItemAdd(attributes as CFDictionary, nil)
        }

        static func load(key: String) -> String? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)

            guard status == errSecSuccess,
                  let data = item as? Data,
                  let value = String(data: data, encoding: .utf8)
            else {
                return nil
            }

            return value
        }

        static func delete(key: String) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}

extension NotificationSettingsManager: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let request = notification.request
        notificationLogger.info("Lifecycle: willPresent notification; identifier=\(request.identifier, privacy: .public) trigger=\(String(describing: request.trigger), privacy: .public)")
        return UNNotificationPresentationOptions(arrayLiteral: .banner, .sound)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        notificationLogger.info("Lifecycle: didReceive notification response; identifier=\(request.identifier, privacy: .public) actionIdentifier=\(response.actionIdentifier, privacy: .public)")
    }
}

private extension UNAuthorizationStatus {
    var debugName: String {
        switch self {
        case .notDetermined:
            "notDetermined"
        case .denied:
            "denied"
        case .authorized:
            "authorized"
        case .provisional:
            "provisional"
        case .ephemeral:
            "ephemeral"
        @unknown default:
            "unknown"
        }
    }
}

/// Injects the subscription's bearer key into generated-client requests; skips
/// the header while no key exists yet (register runs before one is issued).
private struct BearerAuthMiddleware: ClientMiddleware {
    let token: @Sendable () -> String?

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if let token = token() {
            request.headerFields[.authorization] = "Bearer \(token)"
        }
        return try await next(request, body, baseURL)
    }
}
