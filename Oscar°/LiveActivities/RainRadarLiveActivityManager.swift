//
//  RainRadarLiveActivityManager.swift
//  Oscar°
//

import ActivityKit
import Foundation
import OSLog

/// Keeps the server able to reach the rain card and cleans up what it can't.
/// Started from the app delegate on every launch, including the background wake
/// iOS gives the app after a push-to-start: that wake is when the per-activity
/// update token arrives, and without it the server can never end the card.
@MainActor
final class RainRadarLiveActivityManager {
    static let shared = RainRadarLiveActivityManager()

    // Read from the nonisolated reconcile/end path, hence explicitly nonisolated.
    /// The server updates every 10 minutes and ends a card within 45 minutes of
    /// losing contact; content older than this has no server behind it any more.
    nonisolated static let abandonedAfter: TimeInterval = 60 * 60
    nonisolated static let previewSubscriptionId = "preview"

    nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "LiveActivities")
    /// Xcode's preview host launches the app without the Live Activity daemon behind
    /// it; ActivityKit calls then stall the launch the canvas is waiting for.
    nonisolated private static let isPreviewHost =
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    private var isMonitoring = false
    private var observedActivityIds: Set<String> = []

    private init() {}

    func startMonitoring() {
        guard !Self.isPreviewHost, !isMonitoring else { return }
        isMonitoring = true
        Task { await observePushToStartTokens() }
        Task { await observeActivities() }
    }

    /// Ends cards the server can't or won't end: the feature switched off, a card
    /// superseded by a newer one, an ended card past its dismissal time, or one whose
    /// content stopped updating. Runs on launch, on foreground and on every change.
    ///
    /// Off the main actor on purpose: `Activity` is not Sendable and ending one is a
    /// nonisolated async call, so the cards are fetched and ended in one isolation
    /// domain instead of being sent out of the main actor.
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

    /// The person switched the feature (or rain alerts) off: nothing may linger.
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
                // A token for a card the server already ended must not bring it back
                // to life there; only a live card needs its token synced.
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
                    // Ended by the server (a no-op there) or removed by the person or
                    // the system: either way the server must stop targeting it.
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
    /// Starts a local card with sample content so the layout can be checked on a
    /// device without waiting for rain. The server never learns about it; the
    /// Ende button or the reconcile after an hour without updates removes it.
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
