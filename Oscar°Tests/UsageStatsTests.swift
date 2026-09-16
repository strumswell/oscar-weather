import Foundation
import Testing
@testable import Oscar_

struct UsageStatsTests {
    private func extreme(_ value: Double, place: String = "Leipzig") -> UsageStats.Extreme {
        UsageStats.Extreme(value: value, unit: "°C", date: .now, place: place)
    }

    @Test
    func mergeSumsCountersAndKeepsTheRightExtremes() {
        var mine = UsageStats()
        mine.opens = 3
        mine.opensByHour[7] = 2
        mine.dailyOpens["2026-09-16"] = 2
        mine.places["Leipzig"] = 5
        mine.hottest = extreme(30)
        mine.coldest = extreme(-2)
        mine.firstLaunch = Date(timeIntervalSince1970: 2_000)

        var theirs = UsageStats()
        theirs.opens = 4
        theirs.opensByHour[7] = 1
        theirs.dailyOpens["2026-09-16"] = 1
        theirs.dailyOpens["2026-09-15"] = 1
        theirs.places["Berlin"] = 1
        theirs.hottest = extreme(34, place: "Berlin")
        theirs.coldest = extreme(5)
        theirs.firstLaunch = Date(timeIntervalSince1970: 1_000)
        theirs.supporterSince = Date(timeIntervalSince1970: 3_000)

        mine.merge(theirs)

        #expect(mine.opens == 7)
        #expect(mine.opensByHour[7] == 3)
        #expect(mine.dailyOpens["2026-09-16"] == 3)
        #expect(mine.activeDays == 2)
        #expect(mine.places == ["Leipzig": 5, "Berlin": 1])
        #expect(mine.hottest?.place == "Berlin")
        #expect(mine.coldest?.value == -2)
        #expect(mine.firstLaunch == Date(timeIntervalSince1970: 1_000))
        #expect(mine.supporterSince == Date(timeIntervalSince1970: 3_000))
    }

    @Test
    func missingExtremeLosesAgainstAnyValue() {
        #expect(UsageStats.higher(nil, extreme(1))?.value == 1)
        #expect(UsageStats.lower(extreme(1), nil)?.value == 1)
        #expect(UsageStats.higher(nil, nil) == nil)
    }

    @Test
    func decodesABlobWithoutTheOptionalFields() throws {
        let data = try JSONEncoder().encode(UsageStats())
        let decoded = try JSONDecoder().decode(UsageStats.self, from: data)
        #expect(decoded.hottest == nil)
        #expect(decoded.opensByHour.count == 24)
    }
}
