import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

extension NotificationSettingsManager {
    private static let legacyRadarBaseURL = URL(string: "https://radar.oscars.love")!

    func deregisterLegacyRadarSubscriptionIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyDeregistrationCompletedKey) else { return }

        defaults.set(true, forKey: legacyDeregistrationCompletedKey)

        guard let subscriptionId = keychain.load(key: subscriptionKey),
              let apiKey = keychain.load(key: apiKeyKey)
        else {
            notificationLogger.info("Lifecycle: legacy radar de-registration skipped; no stored credentials")
            return
        }

        notificationLogger.info("Lifecycle: legacy radar de-registration request started")

        let legacyBaseURL = Self.legacyRadarBaseURL
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
                let output = try await legacyClient.deleteNotificationSubscription(
                    .init(path: .init(subscriptionId: subscriptionId)))
                notificationLogger.info("Lifecycle: legacy radar de-registration finished; outcome=\(String(describing: output), privacy: .public)")
            } catch {
                notificationLogger.info("Lifecycle: legacy radar de-registration could not reach legacy server; giving up silently (\(error.localizedDescription, privacy: .public))")
            }
        }
    }
}
