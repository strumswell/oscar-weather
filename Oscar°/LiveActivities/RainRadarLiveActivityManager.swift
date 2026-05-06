//
//  RainRadarLiveActivityManager.swift
//  Oscar°
//

import ActivityKit
import Foundation
import OSLog

@MainActor
final class RainRadarLiveActivityManager {
    static let shared = RainRadarLiveActivityManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "LiveActivities")
    private var isMonitoring = false

    private init() {}

    func startMonitoring() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activity monitoring skipped; activities disabled")
            return
        }

        guard !isMonitoring else { return }
        isMonitoring = true

        if #available(iOS 17.2, *) {
            Task { await observePushToStartTokens() }
        }
        Task { await observeActivities() }
    }

    @available(iOS 17.2, *)
    private func observePushToStartTokens() async {
        for await tokenData in Activity<RainRadarActivityAttributes>.pushToStartTokenUpdates {
            let token = tokenData.hexEncodedString()
            logger.info("Received Live Activity push-to-start token; length=\(token.count, privacy: .public)")
            await NotificationSettingsManager.shared.syncLiveActivityPushToStartToken(token)
        }
    }

    private func observeActivities() async {
        for activity in Activity<RainRadarActivityAttributes>.activities {
            observeUpdateTokens(for: activity)
        }

        for await activity in Activity<RainRadarActivityAttributes>.activityUpdates {
            observeUpdateTokens(for: activity)
        }
    }

    private func observeUpdateTokens(for activity: Activity<RainRadarActivityAttributes>) {
        Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.hexEncodedString()
                logger.info("Received Live Activity update token; activityId=\(activity.id, privacy: .public) length=\(token.count, privacy: .public)")
                await NotificationSettingsManager.shared.syncLiveActivityUpdateToken(
                    activityId: activity.id,
                    token: token
                )
            }
        }
    }
}

private extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
