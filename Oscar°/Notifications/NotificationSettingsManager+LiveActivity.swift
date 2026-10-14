import Foundation
import OpenAPIRuntime

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

    func syncLiveActivityPushToStartToken(_ token: String) async {
        UserDefaults.standard.set(token, forKey: liveActivityPushToStartTokenKey)
        await flushPendingLiveActivityReports()
    }

    func syncLiveActivityUpdateToken(activityId: String, token: String) async {
        enqueueLiveActivityReport(.init(kind: .updateToken, activityId: activityId, token: token))
        await flushPendingLiveActivityReports()
    }

    func reportLiveActivityEnded(activityId: String) async {
        var queue = pendingLiveActivityReports.filter { $0.activityId != activityId }
        queue.append(.init(kind: .ended, activityId: activityId, token: nil))
        savePendingLiveActivityReports(queue)
        await flushPendingLiveActivityReports()
    }

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
                dropFirstPendingLiveActivityReport()
                continue
            }
            var body: [String: any Sendable] = ["activityId": report.activityId]
            if let token = report.token { body["token"] = token }
            switch await patchLiveActivity(path: report.kind.rawValue, body: body) {
            case .success, .notFound:
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
