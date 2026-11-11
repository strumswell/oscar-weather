import Foundation
import Testing
@testable import Oscar_

struct PrecipSeriesRateTests {
    private let now = Date(timeIntervalSince1970: 1_754_956_800)

    private func series(_ points: [(minutes: Double, rain: Double)], around date: Date) -> PrecipSeriesResponse {
        PrecipSeriesResponse(
            source: "test",
            unit: "mm/h",
            latitude: 51.34,
            longitude: 12.37,
            series: points.map {
                PrecipPoint(timestamp: date.addingTimeInterval($0.minutes * 60), precipitation: $0.rain, isForecast: $0.minutes > 0)
            },
            generatedAt: nil,
            lastObservedAt: nil,
            forecastHorizon: nil
        )
    }

    @Test
    func nearestPointInsideTheWindowWins() {
        let response = series([(-10, 1.5), (30, 4)], around: now)
        #expect(response.rate(at: now) == 1.5)
    }

    @Test
    func nearestPointOutsideTheWindowIsNil() {
        let response = series([(-21, 1.5), (25, 4)], around: now)
        #expect(response.rate(at: now) == nil)
    }

    @Test
    func emptySeriesIsNil() {
        #expect(series([], around: now).rate(at: now) == nil)
    }

    @Test
    func windowBoundaryIsInclusive() {
        #expect(series([(20, 2)], around: now).rate(at: now) == 2)
        #expect(series([(-20, 2)], around: now).rate(at: now) == 2)
        #expect(series([(20.5, 2)], around: now).rate(at: now) == nil)
    }

    @Test
    func equallyNearPointsKeepTheFirstInSeriesOrder() {
        #expect(series([(5, 3), (-5, 1)], around: now).rate(at: now) == 3)
        #expect(series([(-5, 1), (5, 3)], around: now).rate(at: now) == 1)
    }

    @Test
    func measuredZeroIsAnAnswer() {
        #expect(series([(0, 0)], around: now).rate(at: now) == 0)
    }

    @Test
    func currentRateReadsTheWallClock() {
        #expect(series([(0, 0.7)], around: Date()).currentRate == 0.7)
        #expect(series([(-60, 0.7)], around: Date()).currentRate == nil)
    }
}
