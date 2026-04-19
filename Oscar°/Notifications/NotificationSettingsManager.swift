//
//  NotificationSettingsManager.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.04.26.
//

import Foundation
import OSLog
import Security
import SwiftUI
import UIKit
import UserNotifications

private let notificationLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "Notifications")

@MainActor
final class NotificationSettingsManager: NSObject, ObservableObject {
    static let shared = NotificationSettingsManager()

    @Published private(set) var enabled: Bool
    @Published private(set) var rainAlertsEnabled: Bool
    @Published private(set) var weatherAlertsEnabled: Bool
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let baseURL = URL(string: radarBaseURL)!
    private let locationService = LocationService.shared

    private let rainAlertsEnabledKey = "notificationRainAlertsEnabled"
    private let weatherAlertsEnabledKey = "notificationWeatherAlertsEnabled"
    private let cachedDeviceTokenKey = "rainAlertDeviceToken"
    private let lastSentDeviceTokenKey = "rainAlertLastSentDeviceToken"
    private let subscriptionKey = "rainAlertSubscriptionId"
    private let apiKeyKey = "rainAlertApiKey"
    private let lastSentAPNsEnvironmentKey = "notificationLastSentAPNsEnvironment"
    private let lastSentStateKey = "notificationLastSentState"
    private let installationRegistrationCompletedKey = "notificationInstallationRegistrationCompleted"

    private override init() {
        let defaults = UserDefaults.standard
        let storedRainAlertsEnabled = defaults.bool(forKey: rainAlertsEnabledKey)
        let storedWeatherAlertsEnabled = defaults.bool(forKey: weatherAlertsEnabledKey)

        rainAlertsEnabled = storedRainAlertsEnabled
        weatherAlertsEnabled = storedWeatherAlertsEnabled
        enabled = storedRainAlertsEnabled || storedWeatherAlertsEnabled
        super.init()
    }

    func configureOnLaunch() async {
        UNUserNotificationCenter.current().delegate = self
        notificationLogger.info("Lifecycle: configureOnLaunch started; enabled=\(self.enabled, privacy: .public) storedCredentials=\(self.hasStoredSubscriptionCredentials, privacy: .public)")
        await refreshAuthorizationStatus()

        if hasNotificationAuthorization && (enabled || hasStoredSubscriptionCredentials) {
            notificationLogger.info("Lifecycle: launch prerequisites satisfied; registering for remote notifications")
            UIApplication.shared.registerForRemoteNotifications()
        } else {
            notificationLogger.info("Lifecycle: launch skipped APNs registration; authorization=\(self.authorizationStatus.debugName, privacy: .public) enabled=\(self.enabled, privacy: .public) storedCredentials=\(self.hasStoredSubscriptionCredentials, privacy: .public)")
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

    @available(*, unavailable, message: "Use the individual alert toggles instead.")
    func enableNotifications() async -> Bool {
        let granted = hasNotificationAuthorization ? true : await requestNotificationPermission()
        await refreshAuthorizationStatus()
        guard granted || hasNotificationAuthorization else {
            refreshEnabledState()
            return false
        }

        refreshEnabledState()
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }

    @available(*, unavailable, message: "Use the individual alert toggles instead.")
    func disableNotifications() async {
        setRainAlertsEnabledLocally(false)
        setWeatherAlertsEnabledLocally(false)
        refreshEnabledState()
        await syncSubscriptionForCurrentState(forceRegister: false)
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

    private func refreshEnabledState() {
        enabled = rainAlertsEnabled || weatherAlertsEnabled
    }

    private func notificationSettingsPayload() -> [String: Any] {
        [
            "rainAlertsEnabled": rainAlertsEnabled,
            "weatherAlertsEnabled": weatherAlertsEnabled,
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

        let languageCode: String
        if #available(iOS 16.0, *) {
            languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            languageCode = Locale.current.languageCode ?? "en"
        }
        let language = languageCode.lowercased().hasPrefix("de") ? "de" : "en"

        var patchBody: [String: Any] = [
            "locationLat": outboundCoordinates.latitude,
            "locationLon": outboundCoordinates.longitude,
            "locationName": cityName,
            "timezone": TimeZone.current.identifier,
            "language": language,
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
            rainAlertsEnabled: rainAlertsEnabled,
            weatherAlertsEnabled: weatherAlertsEnabled,
            apnsEnvironment: apnsEnvironment
        )

        let lastSentToken = Keychain.load(key: lastSentDeviceTokenKey)
        let lastSentState = loadLastSentSubscriptionState()
        let registrationCompleted = UserDefaults.standard.bool(forKey: installationRegistrationCompletedKey)
        let shouldRegister = forceRegister
            || !registrationCompleted
            || Keychain.load(key: subscriptionKey) == nil
            || Keychain.load(key: apiKeyKey) == nil
            || lastSentToken != token

        if shouldRegister {
            let reason: String
            if forceRegister {
                reason = "forced"
            } else if !registrationCompleted {
                reason = "installationRegistrationIncomplete"
            } else if Keychain.load(key: subscriptionKey) == nil || Keychain.load(key: apiKeyKey) == nil {
                reason = "missingCredentials"
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

    private func register(body: [String: Any], token: String, state: SentSubscriptionState) async {
        guard let url = URL(string: "/notifications/register", relativeTo: baseURL) else { return }
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return }

        notificationLogger.info("Lifecycle: subscription register request started; payload=\(self.loggablePayload(from: body), privacy: .public)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addAPIContactIdentity()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                notificationLogger.error("Lifecycle: subscription register request failed; status=\(statusCode, privacy: .public)")
                return
            }
            let registerResponse = try JSONDecoder().decode(RegisterResponse.self, from: data)
            Keychain.save(key: subscriptionKey, value: registerResponse.subscriptionId)
            Keychain.save(key: apiKeyKey, value: registerResponse.apiKey)
            Keychain.save(key: lastSentDeviceTokenKey, value: token)
            persistLastSentSubscriptionState(state)
            UserDefaults.standard.set(true, forKey: installationRegistrationCompletedKey)
            notificationLogger.info("Lifecycle: subscription register request succeeded; subscriptionIdLength=\(registerResponse.subscriptionId.count, privacy: .public)")
        } catch {
            notificationLogger.error("Lifecycle: subscription register request threw error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func patchSettings(_ body: [String: Any], token: String, state: SentSubscriptionState) async -> PatchResult {
        guard let subscriptionId = Keychain.load(key: subscriptionKey),
              let apiKey = Keychain.load(key: apiKeyKey),
              let url = URL(string: "/notifications/\(subscriptionId)/settings", relativeTo: baseURL),
              let httpBody = try? JSONSerialization.data(withJSONObject: body)
        else {
            return .notFound
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.addAPIContactIdentity()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = httpBody

        notificationLogger.info("Lifecycle: subscription patch request started; payload=\(self.loggablePayload(from: body), privacy: .public)")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                notificationLogger.error("Lifecycle: subscription patch request failed; response missing HTTPURLResponse")
                return .failure
            }
            if httpResponse.statusCode == 404 {
                Keychain.delete(key: subscriptionKey)
                Keychain.delete(key: apiKeyKey)
                notificationLogger.info("Lifecycle: subscription patch request returned 404; cleared stored credentials")
                return .notFound
            }
            if (200...299).contains(httpResponse.statusCode) {
                Keychain.save(key: lastSentDeviceTokenKey, value: token)
                persistLastSentSubscriptionState(state)
                notificationLogger.info("Lifecycle: subscription patch request succeeded; status=\(httpResponse.statusCode, privacy: .public)")
                return .success
            }
            notificationLogger.error("Lifecycle: subscription patch request failed; status=\(httpResponse.statusCode, privacy: .public)")
            return .failure
        } catch {
            notificationLogger.error("Lifecycle: subscription patch request threw error=\(error.localizedDescription, privacy: .public)")
            return .failure
        }
    }

    private enum PatchResult {
        case success
        case notFound
        case failure
    }

    private struct RegisterResponse: Decodable {
        let subscriptionId: String
        let apiKey: String
    }

    private struct SentSubscriptionState: Codable, Equatable {
        let locationLat: Double
        let locationLon: Double
        let locationName: String
        let timezone: String
        let language: String
        let rainAlertsEnabled: Bool
        let weatherAlertsEnabled: Bool
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

    private func persistLastSentSubscriptionState(_ state: SentSubscriptionState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }

        UserDefaults.standard.set(data, forKey: lastSentStateKey)
        UserDefaults.standard.set(state.apnsEnvironment.rawValue, forKey: lastSentAPNsEnvironmentKey)
    }

    private func loggablePayload(from body: [String: Any]) -> String {
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

extension NotificationSettingsManager: UNUserNotificationCenterDelegate {
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
