import Testing
@testable import Oscar_

struct EUAirQualityBandTests {
    @Test(arguments: [
        (0.0, EUAirQualityBand.good),
        (19.9, EUAirQualityBand.good),
        (20.0, EUAirQualityBand.fair),
        (59.9, EUAirQualityBand.moderate),
        (60.0, EUAirQualityBand.poor),
        (99.9, EUAirQualityBand.veryPoor),
        (100.0, EUAirQualityBand.extremelyPoor),
        (340.0, EUAirQualityBand.extremelyPoor),
    ])
    func bandsSplitAtTheEUThresholds(value: Double, expected: EUAirQualityBand) {
        #expect(EUAirQualityBand(value: value) == expected)
    }

    @Test
    func boundsAreContiguous() {
        let bands = EUAirQualityBand.allCases
        for (lower, upper) in zip(bands, bands.dropFirst()) {
            #expect(lower.upperBound == upper.lowerBound)
        }
        #expect(bands.last?.upperBound == nil)
        #expect(EUAirQualityBand.gradientStops.map(\.location) == [0, 0.2, 0.4, 0.6, 0.8, 1.0])
    }
}
