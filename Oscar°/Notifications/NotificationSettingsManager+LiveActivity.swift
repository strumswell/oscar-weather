import Foundation
import OpenAPIRuntime

extension NotificationSettingsManager {
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

    func patchLiveActivityToken(path: String, body: [String: any Sendable]) async -> Bool {
        guard let subscriptionId = keychain.load(key: subscriptionKey),
              keychain.load(key: apiKeyKey) != nil,
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
    func flushPendingLiveActivityTokens() async {
        guard liveRainStatusEnabled,
              let pending = UserDefaults.standard.string(forKey: pendingLiveActivityPushToStartTokenKey)
        else { return }
        await syncLiveActivityPushToStartToken(pending)
    }
}
