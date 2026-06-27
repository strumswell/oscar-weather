//
//  PollenSeverityTests.swift
//  Oscar°Tests
//
//  Pure-logic tests for pollen tier thresholds and ordering.
//

import Testing
@testable import Oscar_

struct PollenTierTests {
    @Test
    func tiersAreOrdered() {
        #expect(PollenTier.none < .low)
        #expect(PollenTier.low < .moderate)
        #expect(PollenTier.moderate < .high)
        #expect(PollenTier.high < .veryHigh)
    }

    @Test
    func severityFractionSpansZeroToOne() {
        #expect(PollenTier.none.severityFraction == 0)
        #expect(PollenTier.moderate.severityFraction == 0.5)
        #expect(PollenTier.veryHigh.severityFraction == 1.0)
    }
}

struct PollenTypeThresholdTests {
    /// Grass thresholds: <1 none, ≤20 low, ≤50 moderate, ≤150 high, else very high.
    @Test(arguments: [
        (0.0, PollenTier.none), (0.99, .none),
        (1.0, .low), (20.0, .low),
        (21.0, .moderate), (50.0, .moderate),
        (51.0, .high), (150.0, .high),
        (151.0, .veryHigh),
    ])
    func grassTiers(value: Double, expected: PollenTier) {
        #expect(PollenType.grass.tier(for: value) == expected)
    }

    /// Ragweed is far more potent: ≤5 low, ≤11 moderate, ≤40 high, else very high.
    @Test(arguments: [
        (0.5, PollenTier.none),
        (1.0, .low), (5.0, .low),
        (6.0, .moderate), (11.0, .moderate),
        (12.0, .high), (40.0, .high),
        (41.0, .veryHigh),
    ])
    func ragweedTiers(value: Double, expected: PollenTier) {
        #expect(PollenType.ragweed.tier(for: value) == expected)
    }

    @Test
    func displayMaxMatchesType() {
        #expect(PollenType.alder.displayMax == 300)
        #expect(PollenType.birch.displayMax == 300)
        #expect(PollenType.grass.displayMax == 150)
        #expect(PollenType.mugwort.displayMax == 50)
        #expect(PollenType.ragweed.displayMax == 40)
    }
}
