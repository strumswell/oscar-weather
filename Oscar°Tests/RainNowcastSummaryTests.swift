import Foundation
import Testing
@testable import Oscar_

struct RainNowcastSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_754_956_800)

    private func point(minutes: Int, rain: Double) -> PrecipPoint {
        PrecipPoint(timestamp: now.addingTimeInterval(Double(minutes) * 60), precipitation: rain, isForecast: minutes > 0)
    }

    @Test
    func barFractionEmphasizesLightRainAndCapsAtOne() {
        #expect(RainNowcastSummary.barFraction(value: 0, reference: 2) == 0)
        #expect(RainNowcastSummary.barFraction(value: 0.5, reference: 2) == 0.5)
        #expect(RainNowcastSummary.barFraction(value: 8, reference: 2) == 1)
    }

    @Test
    func referenceHasADrizzleFloor() {
        #expect(RainNowcastSummary.reference(for: [0.1, 0.4]) == 2)
        #expect(RainNowcastSummary.reference(for: [3.5, 1]) == 3.5)
        #expect(RainNowcastSummary.reference(for: []) == 2)
    }

    @Test
    func rainEndingSoonNamesTheRemainingMinutes() {
        let points = [point(minutes: 0, rain: 1.2), point(minutes: 5, rain: 0.8), point(minutes: 10, rain: 0)]
        let headline = RainNowcastSummary.headline(for: points, now: now)
        #expect(headline.contains("10"))
    }

    @Test
    func dryWindowAndLaterRainDiffer() {
        let dry = RainNowcastSummary.headline(for: [point(minutes: 0, rain: 0), point(minutes: 5, rain: 0)], now: now)
        let later = RainNowcastSummary.headline(for: [point(minutes: 0, rain: 0), point(minutes: 15, rain: 0.6)], now: now)
        #expect(!dry.isEmpty)
        #expect(dry != later)
    }
}

struct SyntheticRadarTests {
    /// The onboarding's fast grid must match sampling `intensity` per pixel.
    @Test
    func fastGridMatchesPerPixelSampling() {
        for minutes in [0.0, 45, 120] {
            let slow = SyntheticRadar.valueGrid(minutes: minutes) { lat, lon, t in
                let v = SyntheticRadar.intensity(lat: lat, lon: lon, minutes: t)
                return v >= 0.02 ? UInt8(1 + min(219, v * 219)) : 0
            }
            #expect(SyntheticRadar.radarGrid(minutes: minutes) == slow)
        }
    }
}
