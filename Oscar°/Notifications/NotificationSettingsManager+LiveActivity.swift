import Foundation
import OpenAPIRuntime

/// Live Activity bookkeeping toward the server. Reports are queued before they are
/// sent and dropped only once the server acknowledged them: the update token
/// usually arrives during a background wake on a flaky network, and losing it
/// means the server can never end the card.
extension NotificationSettingsManager {
    struct PendingLiveActivityReport: Codable, Equatable {
        enum Kind: String, Codable {
            case updateToken = "update-token"
            case ended
        }

        let kind: Kind
        let activityId: String
        let token: String?
    }

    /// iOS hands the push-to-start token out whenever it likes, feature on or off;
    /// the freshest one is kept and sent once a subscription can use it.
    func syncLiveActivityPushToStartToken(_ token: String) async {
        UserDefaults.standard.set(token, forKey: liveActivityPushToStartTokenKey)
        await flushPendingLiveActivityReports()
    }

    func syncLiveActivityUpdateToken(activityId: String, token: String) async {
        enqueueLiveActivityReport(.init(kind: .updateToken, activityId: activityId, token: token))
        await flushPendingLiveActivityReports()
    }

    func reportLiveActivityEnded(activityId: String) async {
        // An end supersedes a queued token for the same card.
        var queue = pendingLiveActivityReports.filter { $0.activityId != activityId }
        queue.append(.init(kind: .ended, activityId: activityId, token: nil))
        savePendingLiveActivityReports(queue)
        await flushPendingLiveActivityReports()
    }

    /// Sends what is queued, oldest first, stopping at the first failure. Runs after
    /// every enqueue, on launch, on foreground and after a successful register/patch;
    /// a call during a running flush schedules one more pass instead of racing it.
    func flushPendingLiveActivityReports() async {
        guard !liveActivityFlushInProgress else {
            liveActivityFlushRequested = true
            return
        }
        liveActivityFlushInProgress = true
        defer { liveActivityFlushInProgress = false }
        repeat {
            liveActivityFlushRequested = false
            await flushLiveActivityReportsOnce()
        } while liveActivityFlushRequested
    }

    var pendingLiveActivityReports: [PendingLiveActivityReport] {
        guard let data = UserDefaults.standard.data(forKey: pendingLiveActivityReportsKey) else { return [] }
        return (try? JSONDecoder().decode([PendingLiveActivityReport].self, from: data)) ?? []
    }

    private func flushLiveActivityReportsOnce() async {
        guard hasStoredSubscriptionCredentials else { return }
        let defaults = UserDefaults.standard

        if liveRainStatusEnabled,
           let token = defaults.string(forKey: liveActivityPushToStartTokenKey),
           token != defaults.string(forKey: syncedLiveActivityPushToStartTokenKey) {
            guard await patchLiveActivity(path: "push-to-start-token", body: ["token": token]) == .success else {
                return
            }
            defaults.set(token, forKey: syncedLiveActivityPushToStartTokenKey)
        }

        while let report = pendingLiveActivityReports.first {
            if report.kind == .updateToken, !liveRainStatusEnabled {
                // Cards are ended locally while the feature is off; nothing to sync.
                dropFirstPendingLiveActivityReport()
                continue
            }
            var body: [String: any Sendable] = ["activityId": report.activityId]
            if let token = report.token { body["token"] = token }
            switch await patchLiveActivity(path: report.kind.rawValue, body: body) {
            case .success, .notFound:
                // A vanished subscription has nothing left to tell.
                dropFirstPendingLiveActivityReport()
            case .failure:
                return
            }
        }
    }

    private func patchLiveActivity(path: String, body: [String: any Sendable]) async -> PatchResult {
        guard let subscriptionId = keychain.load(key: subscriptionKey),
              keychain.load(key: apiKeyKey) != nil,
              let payload = try? OpenAPIObjectContainer(unvalidatedValue: body.mapValues { $0 as (any Sendable)? })
        else { return .notFound }

        do {
            let output = try await oscarNotifications.patchLiveActivityToken(
                .init(path: .init(subscriptionId: subscriptionId, tokenKind: path), body: .json(.init(additionalProperties: payload))))
            switch output {
            case .ok, .noContent:
                notificationLogger.info("Lifecycle: live-activity \(path, privacy: .public) report delivered")
                return .success
            case .undocumented(let statusCode, _) where statusCode == 404:
                notificationLogger.info("Lifecycle: live-activity \(path, privacy: .public) report returned 404")
                return .notFound
            case .undocumented(let statusCode, _):
                notificationLogger.error("Lifecycle: live-activity \(path, privacy: .public) report failed; status=\(statusCode, privacy: .public)")
                return .failure
            }
        } catch {
            notificationLogger.error("Lifecycle: live-activity \(path, privacy: .public) report threw error=\(error.localizedDescription, privacy: .public)")
            return .failure
        }
    }

    private func enqueueLiveActivityReport(_ report: PendingLiveActivityReport) {
        var queue = pendingLiveActivityReports
        queue.removeAll { $0 == report }
        queue.append(report)
        savePendingLiveActivityReports(queue)
    }

    private func dropFirstPendingLiveActivityReport() {
        var queue = pendingLiveActivityReports
        guard !queue.isEmpty else { return }
        queue.removeFirst()
        savePendingLiveActivityReports(queue)
    }

    private func savePendingLiveActivityReports(_ queue: [PendingLiveActivityReport]) {
        guard !queue.isEmpty, let data = try? JSONEncoder().encode(queue) else {
            UserDefaults.standard.removeObject(forKey: pendingLiveActivityReportsKey)
            return
        }
        UserDefaults.standard.set(data, forKey: pendingLiveActivityReportsKey)
    }
}
