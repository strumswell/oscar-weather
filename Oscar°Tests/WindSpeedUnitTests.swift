//
//  WindSpeedUnitTests.swift
//  Oscar°Tests
//
//  Pure-logic tests for wind-speed unit resolution and the Beaufort conversion.
//

import Testing
@testable import Oscar_

struct WindSpeedUnitTests {
    @Test
    func initFallsBackToKmhForMissingOrUnknownValues() {
        #expect(WindSpeedUnit(settingValue: nil) == .kmh)
        #expect(WindSpeedUnit(settingValue: "") == .kmh)
        #expect(WindSpeedUnit(settingValue: "not-a-unit") == .kmh)
    }

    @Test
    func initParsesKnownRawValues() {
        #expect(WindSpeedUnit(settingValue: "ms") == .ms)
        #expect(WindSpeedUnit(settingValue: "mph") == .mph)
        #expect(WindSpeedUnit(settingValue: "kn") == .kn)
        #expect(WindSpeedUnit(settingValue: "bft") == .bft)
    }

    @Test
    func beaufortReportsKilometersPerHourToTheAPI() {
        // The API has no Beaufort scale, so .bft must request km/h and convert locally.
        #expect(WindSpeedUnit.bft.apiRawValue == "kmh")
        #expect(WindSpeedUnit.ms.apiRawValue == "ms")
        #expect(WindSpeedUnit.kmh.apiRawValue == "kmh")
    }

    @Test
    func onlyBeaufortUsesBeaufortDisplay() {
        #expect(WindSpeedUnit.bft.usesBeaufortDisplay)
        #expect(!WindSpeedUnit.kmh.usesBeaufortDisplay)
        #expect(!WindSpeedUnit.mph.usesBeaufortDisplay)
    }
}

struct BeaufortScaleTests {
    /// Boundary values straight off `BeaufortScale.force(forKilometersPerHour:)`.
    @Test(arguments: [
        (-5.0, 0), (0.0, 0), (0.99, 0),
        (1.0, 1), (5.99, 1),
        (6.0, 2), (11.99, 2),
        (12.0, 3), (20.0, 4), (29.0, 5), (39.0, 6),
        (50.0, 7), (62.0, 8), (75.0, 9), (89.0, 10),
        (103.0, 11), (118.0, 12), (200.0, 12),
    ])
    func forceMatchesScaleBoundaries(speed: Double, expectedForce: Int) {
        #expect(BeaufortScale.force(forKilometersPerHour: speed) == expectedForce)
    }

    @Test
    func entryForForceClampsOutOfRange() {
        #expect(BeaufortScale.entry(forForce: -3).force == 0)
        #expect(BeaufortScale.entry(forForce: 99).force == 12)
        #expect(BeaufortScale.entry(forForce: 5).force == 5)
    }

    @Test
    func valueForNilSpeedIsNil() {
        #expect(BeaufortScale.value(forKilometersPerHour: nil) == nil)
        #expect(BeaufortScale.value(forKilometersPerHour: 50) == 7.0)
    }

    @Test
    func convertedValuesMapElementwise() {
        #expect(BeaufortScale.convertedValues(fromKilometersPerHour: [0, 6, 39]) == [0, 2, 6])
    }
}
