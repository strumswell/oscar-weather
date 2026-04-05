//
//  WeatherApp.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.
//

import SwiftUI
import Sentry
import SentrySwiftUI
import CoreLocation
import UserNotifications
import UIKit
import Security

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            RainAlertManager.shared.didRegisterForRemoteNotifications(deviceToken)
        }
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("APNs registration failed: \(error.localizedDescription)")
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
            options.enableTracing = true
            options.tracesSampleRate = 0.5

            options.attachScreenshot = true
            options.attachViewHierarchy = true
            options.enableMetricKit = true
            options.enableTimeToFullDisplayTracing = true
            options.swiftAsyncStacktraces = true
            options.enableAppLaunchProfiling = true
        }
    }
    
    @State private var weather = Weather()
    @State private var location = Location()
    private let locationService = LocationService.shared
    private let client = APIClient()
    private let persistenceController = PersistenceController.shared
    @StateObject private var rainAlertManager = RainAlertManager.shared
    
    var body: some Scene {
        WindowGroup {
            NowView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(weather)
                .environment(location)
                .preferredColorScheme(.dark)
                .task {
                    await updateState()
                    await rainAlertManager.configureOnLaunch()
                }
                .sentryTrace("NowView")
        }
    }
}

extension WeatherApp {
    public func updateState() async {
        do {
            if weather.isLoading { return }
            weather.isLoading = true
            
            locationService.update()
            location = await locationService.getLocation()
                        
            async let forecastRequest = client.getForecast(coordinates: location.coordinates)
            async let airQualityRequest = client.getAirQuality(coordinates: location.coordinates)
            async let radarRequest = client.getRainRadar(coordinates: location.coordinates)
            let (forecastResponse, airQualityResponse, radarResponse) = try await (forecastRequest, airQualityRequest, radarRequest)
            weather.forecast = forecastResponse
            weather.air = airQualityResponse
            weather.radar = radarResponse
            weather.updateTime()
            weather.isLoading = false
            
            let alertsResponse = try await client.getAlerts(coordinates: location.coordinates)
            weather.alerts = alertsResponse
        } catch {
            print(error)
            weather.error = error.localizedDescription
        }
    }
}

@MainActor
final class RainAlertManager: NSObject, ObservableObject {
    static let shared = RainAlertManager()
    
    @Published private(set) var isEnabled: Bool
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    private let baseURL = URL(string: "https://radar.oscars.love")!
    private let locationService = LocationService.shared
    
    private let appEnabledKey = "rainAlertEnabledInApp"
    private let cachedDeviceTokenKey = "rainAlertDeviceToken"
    private let subscriptionKey = "rainAlertSubscriptionId"
    private let apiKeyKey = "rainAlertApiKey"
    
    private override init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: appEnabledKey)
        super.init()
    }
    
    func configureOnLaunch() async {
        UNUserNotificationCenter.current().delegate = self
        await refreshAuthorizationStatus()
        
        guard isEnabled else { return }
        
        if authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral {
            UIApplication.shared.registerForRemoteNotifications()
            await syncRegistrationForCurrentLocation(forceRegister: true)
        }
    }
    
    func enableAlerts() async -> Bool {
        let granted = await requestNotificationPermission()
        await refreshAuthorizationStatus()
        guard granted else {
            setAppEnabled(false)
            return false
        }
        
        setAppEnabled(true)
        UIApplication.shared.registerForRemoteNotifications()
        
        if RainAlertKeychain.load(key: cachedDeviceTokenKey) != nil {
            await syncRegistrationForCurrentLocation(forceRegister: true)
        }
        
        return true
    }
    
    func disableAlerts() async {
        setAppEnabled(false)
        await patchSettings([
            "enabled": false
        ])
    }
    
    func didRegisterForRemoteNotifications(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        RainAlertKeychain.save(key: cachedDeviceTokenKey, value: token)
        
        guard isEnabled else { return }
        Task {
            await self.syncRegistrationForCurrentLocation(forceRegister: true)
        }
    }
    
    func syncLocationUpdate() async {
        guard isEnabled else { return }
        await syncRegistrationForCurrentLocation(forceRegister: false)
    }
    
    func reloadNotificationStatus() async {
        await refreshAuthorizationStatus()
    }
    
    private func setAppEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: appEnabledKey)
    }
    
    private func requestNotificationPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func refreshAuthorizationStatus() async {
        authorizationStatus = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }
    
    private func syncRegistrationForCurrentLocation(forceRegister: Bool) async {
        guard let token = RainAlertKeychain.load(key: cachedDeviceTokenKey), !token.isEmpty else { return }
        
        locationService.update()
        let currentLocation = await locationService.getLocation()
        let cityName = currentLocation.name.isEmpty ? "Current Location" : currentLocation.name
        
        let languageCode: String
        if #available(iOS 16.0, *) {
            languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            languageCode = Locale.current.languageCode ?? "en"
        }
        let language = languageCode.lowercased().hasPrefix("de") ? "de" : "en"
        
        let body: [String: Any] = [
            "deviceToken": token,
            "locationLat": currentLocation.coordinates.latitude,
            "locationLon": currentLocation.coordinates.longitude,
            "locationName": cityName,
            "timezone": TimeZone.current.identifier,
            "language": language
        ]
        
        if forceRegister || RainAlertKeychain.load(key: subscriptionKey) == nil || RainAlertKeychain.load(key: apiKeyKey) == nil {
            await register(body: body)
        } else {
            await patchSettings([
                "locationLat": currentLocation.coordinates.latitude,
                "locationLon": currentLocation.coordinates.longitude,
                "locationName": cityName,
                "timezone": TimeZone.current.identifier,
                "language": language,
                "enabled": true
            ])
        }
    }
    
    private func register(body: [String: Any]) async {
        guard let url = URL(string: "/notifications/register", relativeTo: baseURL) else { return }
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return
            }
            let registerResponse = try JSONDecoder().decode(RainAlertRegisterResponse.self, from: data)
            RainAlertKeychain.save(key: subscriptionKey, value: registerResponse.subscriptionId)
            RainAlertKeychain.save(key: apiKeyKey, value: registerResponse.apiKey)
        } catch {
            print("Rain alert register failed: \(error.localizedDescription)")
        }
    }
    
    private func patchSettings(_ body: [String: Any]) async {
        guard let subscriptionId = RainAlertKeychain.load(key: subscriptionKey),
              let apiKey = RainAlertKeychain.load(key: apiKeyKey),
              let url = URL(string: "/notifications/\(subscriptionId)/settings", relativeTo: baseURL),
              let httpBody = try? JSONSerialization.data(withJSONObject: body)
        else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = httpBody
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }
            if httpResponse.statusCode == 404 {
                RainAlertKeychain.delete(key: subscriptionKey)
                RainAlertKeychain.delete(key: apiKeyKey)
            }
        } catch {
            print("Rain alert patch failed: \(error.localizedDescription)")
        }
    }
}

extension RainAlertManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

private struct RainAlertRegisterResponse: Decodable {
    let subscriptionId: String
    let apiKey: String
}

private enum RainAlertKeychain {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemAdd(attributes as CFDictionary, nil)
    }
    
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
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
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
