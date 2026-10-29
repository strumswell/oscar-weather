import Foundation
import Testing
@testable import Oscar_

struct ClubCodesTests {
    @Test func sealedRewardOpensOnlyWithItsCode() throws {
        let reward = ClubReward(tier: "founder", years: 3, titles: ["Wetterfrosch"], stickers: ["*"])
        let sealed = try ClubCodes.seal(reward, code: "1a2b-3c4d-5e6f")
        let table = [sealed.id: sealed.box]
        #expect(try ClubCodes.open("1A2B3C4D5E6F", in: table).reward == reward)
        #expect(throws: ClubCodes.Failure.self) { try ClubCodes.open("1A2B3C4D5E60", in: table) }
    }

    @Test func unlocksMerge() {
        let unlocks = ClubUnlocks([
            ClubReward(tier: "supporter", years: 2),
            ClubReward(tier: "founder", years: 5, titles: ["A"], stickers: ["sticker_pest"])
        ])
        #expect(unlocks.founder && unlocks.supporter)
        #expect(unlocks.years == 5)
        #expect(unlocks.unlocksSticker("sticker_pest"))
        #expect(!unlocks.unlocksSticker("sticker_qourses"))
        var stats = UsageStats()
        stats.firstLaunch = .now
        let status = MemberStatus(stats: stats, isSupporter: false, chosenTitle: "A", unlocks: unlocks)
        #expect(status.tier == .founderSupporter)
        #expect(status.years == 5)
        #expect(status.title == "A")

        let redeemed = Date.now.addingTimeInterval(-2.1 * 365 * 86_400)
        #expect(ClubUnlocks([ClubReward(years: 3, redeemedAt: redeemed)]).years == 5)

        stats.firstLaunch = .now.addingTimeInterval(-7.2 * 365 * 86_400)
        #expect(MemberStatus(stats: stats, isSupporter: false, chosenTitle: nil, unlocks: unlocks).years == 7)
    }
}
