import Foundation
import Testing
@testable import Oscar_

struct RainNowcastSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_754_956_800)

    private func point(minutes: Int, rain: Double) -> PrecipPoint {
        PrecipPoint(timestamp: now.addingTimeInterval(Double(minutes) * 60), precipitation: rain, isForecast: minutes > 0)
    }

    @Test
    func radarDecidesTheConditionBothWays() {
        #expect(WeatherConditionLabel.code(weathercode: 2, radarRate: nil) == 2)
        #expect(WeatherConditionLabel.code(weathercode: 61, radarRate: nil) == 61)
        #expect(WeatherConditionLabel.code(weathercode: 2, radarRate: 0.4) == 51)
        #expect(WeatherConditionLabel.code(weathercode: 3, radarRate: 3) == 61)
        #expect(WeatherConditionLabel.code(weathercode: 61, radarRate: 0) == 3)
        #expect(WeatherConditionLabel.code(weathercode: 73, radarRate: 1) == 73)
    }

    @Test
    func radarKindReplacesTheForecastWord() {
        #expect(WeatherConditionLabel.code(61, radarKind: "sleet") == 68)
        #expect(WeatherConditionLabel.code(73, radarKind: "sleet") == 68)
        #expect(WeatherConditionLabel.code(51, radarKind: "snow") == 71)
        #expect(WeatherConditionLabel.code(73, radarKind: "rain") == 61)
        #expect(WeatherConditionLabel.code(63, radarKind: "rain") == 63)
        #expect(WeatherConditionLabel.code(63, radarKind: nil) == 63)
        #expect(WeatherConditionLabel.code(95, radarKind: "snow") == 95)
    }

    @Test
    func headlineUsesThePlaceTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let points = [point(minutes: 0, rain: 0), point(minutes: 15, rain: 0.6)]
        let start = SettingService.formattedTime(now.addingTimeInterval(15 * 60), timeZone: tokyo)
        #expect(RainNowcastSummary.headline(for: points, now: now, timeZone: tokyo) == String(localized: "Regen ab \(start)"))
    }

    @Test
    func rainEndingSoonNamesTheRemainingMinutes() {
        let points = [point(minutes: 0, rain: 1.2), point(minutes: 5, rain: 0.8), point(minutes: 10, rain: 0)]
        let headline = RainNowcastSummary.headline(for: points, now: now)
        let minutes = 10
        #expect(headline == String(localized: "Regen · noch ~\(minutes) min"))
    }

    @Test
    func dryWindowAndLaterRainDiffer() {
        let dry = RainNowcastSummary.headline(for: [point(minutes: 0, rain: 0), point(minutes: 5, rain: 0)], now: now)
        let later = RainNowcastSummary.headline(for: [point(minutes: 0, rain: 0), point(minutes: 15, rain: 0.6)], now: now)
        let start = SettingService.formattedTime(now.addingTimeInterval(15 * 60))
        #expect(dry == String(localized: "Kein Regen in Sicht"))
        #expect(later == String(localized: "Regen ab \(start)"))
        #expect(dry != later)
    }
}
