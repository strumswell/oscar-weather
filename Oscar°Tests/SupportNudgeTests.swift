import Foundation
import Testing
@testable import Oscar_

struct SupportNudgeTests {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    private func stats(activeDays: Int, opens: Int) -> UsageStats {
        var stats = UsageStats()
        stats.opens = opens
        for day in 0..<activeDays {
            stats.dailyOpens["day\(day)"] = 1
        }
        return stats
    }

    @Test
    func firstAskNeedsRepeatedUse() {
        let regular = stats(activeDays: 7, opens: 20)
        #expect(SupportNudge.isDue(stats: regular, isSupporter: false, nextAsk: nil, now: now))
        #expect(!SupportNudge.isDue(stats: regular, isSupporter: true, nextAsk: nil, now: now))
        #expect(!SupportNudge.isDue(stats: stats(activeDays: 6, opens: 50), isSupporter: false, nextAsk: nil, now: now))
        #expect(!SupportNudge.isDue(stats: stats(activeDays: 10, opens: 19), isSupporter: false, nextAsk: nil, now: now))
    }

    @Test
    func afterADismissalOnlyTheBackoffCounts() {
        let fresh = stats(activeDays: 0, opens: 0)
        #expect(!SupportNudge.isDue(stats: fresh, isSupporter: false, nextAsk: now.addingTimeInterval(1), now: now))
        #expect(SupportNudge.isDue(stats: fresh, isSupporter: false, nextAsk: now, now: now))
    }

    @Test
    func backoffDoublesUpToHalfAYear() {
        let days = (1...6).map { SupportNudge.nextAsk(afterDismissals: $0, now: now).timeIntervalSince(now) / 86_400 }
        #expect(days == [14, 28, 56, 112, 180, 180])
    }
}
