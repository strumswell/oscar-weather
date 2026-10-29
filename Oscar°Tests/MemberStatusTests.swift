import Foundation
import Testing
@testable import Oscar_

struct MemberStatusTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func stats(firstLaunch: TimeInterval = -10 * 86_400) -> UsageStats {
        var stats = UsageStats()
        stats.firstLaunch = now.addingTimeInterval(firstLaunch)
        return stats
    }

    @Test func tiers() {
        var plain = stats()
        #expect(MemberStatus(stats: plain, isSupporter: false, chosenTitle: nil, now: now).tier == .member)
        #expect(MemberStatus(stats: plain, isSupporter: true, chosenTitle: nil, now: now).tier == .supporter)
        plain.betaSince = now.addingTimeInterval(-86_400)
        #expect(MemberStatus(stats: plain, isSupporter: false, chosenTitle: nil, now: now).tier == .founder)
        plain.supporterSince = now
        #expect(MemberStatus(stats: plain, isSupporter: false, chosenTitle: nil, now: now).tier == .founderSupporter)
    }

    @Test func yearsCountFromEarliestDate() {
        var stats = stats()
        stats.betaSince = now.addingTimeInterval(-3.2 * 365 * 86_400)
        let status = MemberStatus(stats: stats, isSupporter: false, chosenTitle: nil, now: now)
        #expect(status.years == 3)
        #expect(status.since == stats.betaSince)
    }

    @Test func betaSinceMergesToEarliest() {
        var mine = stats()
        var other = stats()
        mine.betaSince = now
        other.betaSince = now.addingTimeInterval(-100)
        mine.merge(other)
        #expect(mine.betaSince == now.addingTimeInterval(-100))

        var empty = stats()
        empty.merge(other)
        #expect(empty.betaSince == other.betaSince)
    }

    @Test func titlesFollowStatsAndChoice() {
        var stats = stats()
        stats.coldest = UsageStats.Extreme(value: -22, unit: "°C", date: now, place: "Davos")
        stats.windiest = UsageStats.Extreme(value: 70, unit: "mph", date: now, place: "Sylt")
        let earned = MemberStatus(stats: stats, isSupporter: false, chosenTitle: nil, now: now)
        #expect(earned.earnedTitles == ["Minus 20 Club", "Storm Watcher"])
        #expect(earned.title == "Minus 20 Club")
        #expect(MemberStatus(stats: stats, isSupporter: false, chosenTitle: "Storm Watcher", now: now).title == "Storm Watcher")
        #expect(MemberStatus(stats: stats, isSupporter: false, chosenTitle: "Heatwave", now: now).title == "Minus 20 Club")
        #expect(MemberStatus(stats: stats, isSupporter: false, chosenTitle: "", now: now).title == nil)
    }

    @Test func stylesFollowEntitlement() {
        #expect(MemberTier.member.styles == [.member])
        #expect(MemberTier.supporter.styles == [.member, .supporter])
        #expect(MemberTier.founder.styles == [.member, .founder])
        #expect(MemberTier.founderSupporter.styles == MemberTier.allCases)

        var stats = stats()
        #expect(MemberStatus(stats: stats, isSupporter: false, chosenTitle: nil, chosenStyle: .founder, now: now).style == .member)
        stats.betaSince = now
        let founder = MemberStatus(stats: stats, isSupporter: false, chosenTitle: nil, chosenStyle: .member, now: now)
        #expect(founder.tier == .founder)
        #expect(founder.style == .member)
    }

    @Test func stampsPerTierAndYears() {
        #expect(MemberCardStampSpec.specs(tier: .member, years: 0, seed: 0).isEmpty)
        #expect(MemberCardStampSpec.specs(tier: .founder, years: 0, seed: 0).map(\.shape) == [.rect])
        #expect(MemberCardStampSpec.specs(tier: .member, years: 5, seed: 0).map(\.shape) == [.scallop])
        #expect(MemberCardStampSpec.specs(tier: .founderSupporter, years: 12, seed: 0).map(\.shape) == [.rect, .double])
    }
}
