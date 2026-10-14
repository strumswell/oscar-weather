//
//  RainRadarLiveActivityManager.swift
//  Oscar°
//

import ActivityKit
import Foundation
import OSLog
import UIKit

@MainActor
final class RainRadarLiveActivityManager {
    static let shared = RainRadarLiveActivityManager()

    nonisolated static let abandonedAfter: TimeInterval = 60 * 60
    nonisolated static let previewSubscriptionId = "preview"

    nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "LiveActivities")
    nonisolated private static let isPreviewHost =
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    private var isMonitoring = false
    private var observedActivityIds: Set<String> = []

    private init() {}

    static var isSupported: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    func startMonitoring() {
        guard Self.isSupported, !Self.isPreviewHost, !isMonitoring else { return }
        isMonitoring = true
        Task { await observePushToStartTokens() }
        Task { await observeActivities() }
    }

    nonisolated func reconcile(now: Date = Date()) async {
        guard !Self.isPreviewHost else { return }
        let enabled = await NotificationSettingsManager.shared.liveRainStatusEnabled
        let activities = Activity<RainRadarActivityAttributes>.activities
        let live = activities.filter {
            ($0.activityState == .active || $0.activityState == .stale)
                && $0.attributes.subscriptionId != Self.previewSubscriptionId
        }
        let newest = live.max { $0.content.state.observedAt < $1.content.state.observedAt }

        for activity in activities {
            let state = activity.content.state
            let isPreview = activity.attributes.subscriptionId == Self.previewSubscriptionId
            let reason: String?
            if let dismissAt = state.dismissDate, now >= dismissAt {
                reason = "dismissal time passed"
            } else if activity.activityState == .ended || activity.activityState == .dismissed {
                reason = nil
            } else if !enabled, !isPreview {
                reason = "live rain status disabled"
            } else if now.timeIntervalSince(state.observedDate) > Self.abandonedAfter {
                reason = "no update for \(Int(Self.abandonedAfter / 60)) min"
            } else if let newest, activity.id != newest.id, !isPreview {
                reason = "superseded by \(newest.id)"
            } else {
                reason = nil
            }
            guard let reason else { continue }
            await end(activity, reason: reason)
        }
    }

    nonisolated func endAll() async {
        guard !Self.isPreviewHost else { return }
        for activity in Activity<RainRadarActivityAttributes>.activities {
            await end(activity, reason: "ended by the app")
        }
    }

    nonisolated private func end(_ activity: Activity<RainRadarActivityAttributes>, reason: String) async {
        let activityId = activity.id
        logger.info("Ending activity \(activityId, privacy: .public): \(reason, privacy: .public)")
        await activity.end(nil, dismissalPolicy: .immediate)
        await stopObserving(activityId)
        await NotificationSettingsManager.shared.reportLiveActivityEnded(activityId: activityId)
    }

    private func stopObserving(_ activityId: String) {
        observedActivityIds.remove(activityId)
    }

    private func observePushToStartTokens() async {
        for await tokenData in Activity<RainRadarActivityAttributes>.pushToStartTokenUpdates {
            let token = tokenData.hexEncodedString()
            logger.info("Push-to-start token received; length=\(token.count, privacy: .public)")
            await NotificationSettingsManager.shared.syncLiveActivityPushToStartToken(token)
        }
    }

    private func observeActivities() async {
        for activity in Activity<RainRadarActivityAttributes>.activities {
            observe(activity)
        }
        await reconcile()
        for await activity in Activity<RainRadarActivityAttributes>.activityUpdates {
            observe(activity)
            await reconcile()
        }
    }

    private func observe(_ activity: Activity<RainRadarActivityAttributes>) {
        guard observedActivityIds.insert(activity.id).inserted else { return }
        logger.info("Observing activity \(activity.id, privacy: .public); phase=\(activity.content.state.phase.rawValue, privacy: .public)")
        Task {
            for await tokenData in activity.pushTokenUpdates {
                guard activity.activityState == .active || activity.activityState == .stale else { continue }
                let token = tokenData.hexEncodedString()
                logger.info("Update token received; activityId=\(activity.id, privacy: .public) length=\(token.count, privacy: .public)")
                await NotificationSettingsManager.shared.syncLiveActivityUpdateToken(activityId: activity.id, token: token)
            }
        }
        Task {
            for await state in activity.activityStateUpdates {
                switch state {
                case .ended, .dismissed:
                    observedActivityIds.remove(activity.id)
                    await NotificationSettingsManager.shared.reportLiveActivityEnded(activityId: activity.id)
                case .stale:
                    await reconcile()
                default:
                    break
                }
            }
        }
    }

    #if DEBUG
    func startPreview(phase: RainRadarActivityAttributes.ContentState.Phase) throws {
        let content = RainRadarActivityAttributes.ContentState.sample(phase: phase)
        _ = try Activity.request(
            attributes: RainRadarActivityAttributes(locationName: "Leipzig", subscriptionId: Self.previewSubscriptionId),
            content: .init(state: content, staleDate: Date().addingTimeInterval(30 * 60)),
            pushType: nil
        )
    }
    #endif
}

private extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
