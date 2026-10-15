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
    func extremesCompareAcrossUnits() {
        let celsius = extreme(25)
        let fahrenheit = UsageStats.Extreme(value: 75, unit: "°F", date: .now, place: "Leipzig")
        let hottest = UsageStats.higher(celsius, fahrenheit)
        #expect(hottest?.unit == "°C")
        #expect(hottest?.value == 25)
        let coldest = UsageStats.lower(celsius, fahrenheit)
        #expect(abs((coldest?.value ?? 0) - 23.888) < 0.01)
        #expect(abs(UsageStats.Extreme(value: 10, unit: "m/s", date: .now, place: "").canonical.value - 36) < 0.001)
        #expect(abs(UsageStats.Extreme(value: 1, unit: "inch", date: .now, place: "").canonical.value - 25.4) < 0.001)
        #expect(abs(celsius.converted(to: "°F").value - 77) < 0.001)
    }

    @Test
    func streaksCountConsecutiveDays() {
        var stats = UsageStats()
        for day in ["2026-10-01", "2026-10-02", "2026-10-03", "2026-10-10", "2026-10-11"] {
            stats.dailyOpens[day] = 1
        }
        let now = Date(timeIntervalSince1970: 1_791_720_000)
        let streaks = stats.streaks(now: now)
        #expect(streaks.longest == 3)
        #expect(streaks.current == 2)
    }

    @Test
    func oscarServerCallsAreGroupedByArea() {
        #expect(UsageCountingMiddleware.key(host: "server.oscars.love", operationID: "getRadarGrid") == "server.oscars.love/radar")
        #expect(UsageCountingMiddleware.key(host: "server.oscars.love", operationID: "getModelTile") == "server.oscars.love/layers")
        #expect(UsageCountingMiddleware.key(host: "server.oscars.love", operationID: "patchLiveActivityToken") == "server.oscars.love/notifications")
        #expect(UsageCountingMiddleware.key(host: "api.open-meteo.com", operationID: "getForecast") == "api.open-meteo.com")
    }

    @Test
    func decodesABlobWithoutTheOptionalFields() throws {
        let data = try JSONEncoder().encode(UsageStats())
        let decoded = try JSONDecoder().decode(UsageStats.self, from: data)
        #expect(decoded.hottest == nil)
        #expect(decoded.opensByHour.count == 24)
    }
}
