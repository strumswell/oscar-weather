import Foundation

/// When Oscar the cat asks for support. Only after real, repeated use, never
/// supporters, and every "not now" (or an ignored ask) doubles the wait.
/// The back-off is mirrored to iCloud, like the usage stats it's checked against.
enum SupportNudge {
    enum Pose: CaseIterable {
        case rappel, peek, diver

        var imageName: String { "nudge_\(self)" }
    }

    static let minActiveDays = 7
    static let minOpens = 20
    static let firstBackoffDays = 14.0
    static let maxBackoffDays = 180.0

    static let line: LocalizedStringResource = "Gefällt dir Oscar?"

    private static let dismissalsKey = "supportNudgeDismissals"
    private static let nextAskKey = "supportNudgeNextAsk"
    private static var cloud: NSUbiquitousKeyValueStore { .default }

    /// `-supportNudge YES` or the debug panel's switch skips every rule, for trying it out.
    static let forcedKey = "supportNudge"
    static var isForced: Bool { UserDefaults.standard.bool(forKey: forcedKey) }

    static var dismissals: Int {
        max(AppGroup.defaults.integer(forKey: dismissalsKey), Int(cloud.longLong(forKey: dismissalsKey)))
    }

    private static var scheduledAsk: Date? {
        [AppGroup.defaults.object(forKey: nextAskKey), cloud.object(forKey: nextAskKey)]
            .compactMap { $0 as? Date }
            .max()
    }

    static var pose: Pose { Pose.allCases[dismissals % Pose.allCases.count] }

    @MainActor static var isDue: Bool {
        if isForced { return true }
        guard !ScreenshotMode.active else { return false }
        return isDue(
            stats: UsageStatsStore.shared.combined,
            isSupporter: SupporterStore.shared.isSupporter,
            nextAsk: scheduledAsk,
            now: .now
        )
    }

    static func isDue(stats: UsageStats, isSupporter: Bool, nextAsk: Date?, now: Date) -> Bool {
        guard !isSupporter else { return false }
        if let nextAsk { return now >= nextAsk }
        return stats.activeDays >= minActiveDays && stats.opens >= minOpens
    }

    /// 14, 28, 56, 112, then 180 days.
    static func nextAsk(afterDismissals count: Int, now: Date) -> Date {
        let days = min(firstBackoffDays * pow(2, Double(max(count - 1, 0))), maxBackoffDays)
        return now.addingTimeInterval(days * 86_400)
    }

    static func recordDismissal() {
        guard !isForced else { return }
        let count = dismissals + 1
        let next = nextAsk(afterDismissals: count, now: .now)
        AppGroup.defaults.set(count, forKey: dismissalsKey)
        AppGroup.defaults.set(next, forKey: nextAskKey)
        cloud.set(Int64(count), forKey: dismissalsKey)
        cloud.set(next, forKey: nextAskKey)
    }
}
