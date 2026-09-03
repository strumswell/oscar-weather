import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

extension NotificationSettingsManager {
    /// Old notification backend the app used before migrating to ``radarBaseURL`` (server.oscars.love).
    private static let legacyRadarBaseURL = URL(string: "https://radar.oscars.love")!

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
    func deregisterLegacyRadarSubscriptionIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyDeregistrationCompletedKey) else { return }

        // Fire-once: regardless of outcome (deleted, already gone, or legacy server
        // offline) we never attempt this again.
        defaults.set(true, forKey: legacyDeregistrationCompletedKey)

        guard let subscriptionId = keychain.load(key: subscriptionKey),
              let apiKey = keychain.load(key: apiKeyKey)
        else {
            // Nothing was ever registered (e.g. fresh install); no legacy cleanup required.
            notificationLogger.info("Lifecycle: legacy radar de-registration skipped; no stored credentials")
            return
        }

        notificationLogger.info("Lifecycle: legacy radar de-registration request started")

        // Fire-and-forget on a one-off client: the credentials are captured by value, so a
        // later re-registration overwriting the Keychain cannot affect it, and launch is
        // never blocked on the legacy host (10 s request timeout).
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
}
