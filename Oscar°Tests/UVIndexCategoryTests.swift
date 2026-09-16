import Testing
@testable import Oscar_

struct UVIndexCategoryTests {
    @Test(arguments: [
        (0.0, UVIndexCategory.low),
        (2.4, UVIndexCategory.low),
        (2.6, UVIndexCategory.moderate),
        (5.4, UVIndexCategory.moderate),
        (6.0, UVIndexCategory.high),
        (7.6, UVIndexCategory.veryHigh),
        (10.4, UVIndexCategory.veryHigh),
        (11.0, UVIndexCategory.extreme),
    ])
    func categoriesFollowTheRoundedIndex(value: Double, expected: UVIndexCategory) {
        #expect(UVIndexCategory(uvIndex: value) == expected)
    }

    @Test
    func bandsTileTheScaleWithoutGaps() {
        let bands = UVIndexCategory.allCases.map(\.range)
        for (lower, upper) in zip(bands, bands.dropFirst()) {
            #expect(lower.upperBound == upper.lowerBound)
        }
        #expect(bands.first?.lowerBound == 0)
    }
}
