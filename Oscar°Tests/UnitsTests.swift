//
//  UnitsTests.swift
//  Oscar°Tests
//
//  Pure-logic tests for metric-to-display unit conversion and the Beaufort scale.
//

import Testing
@testable import Oscar_

struct UnitsTests {
    @Test
    func temperatureConvertsFromCelsius() {
        #expect(TemperatureUnit.fahrenheit.value(fromCelsius: 0) == 32)
        #expect(TemperatureUnit.fahrenheit.value(fromCelsius: 100) == 212)
        #expect(TemperatureUnit.fahrenheit.delta(fromCelsius: 10) == 18)
        #expect(TemperatureUnit.celsius.value(fromCelsius: 21.4) == 21.4)
        #expect(TemperatureUnit.fahrenheit.celsius(fromValue: 212) == 100)
    }

    @Test
    func temperatureStringRoundsWithoutNegativeZero() {
        #expect(Units.metric.temperatureString(-0.4) == "0°")
        #expect(Units.metric.temperatureString(21.6) == "22°")
        #expect(Units.metric.temperatureString(nil) == "")
        var units = Units.metric
        units.temperature = .fahrenheit
        #expect(units.temperatureString(20) == "68°")
    }

    @Test
    func windConvertsFromKilometersPerHour() {
        #expect(WindSpeedUnit.kmh.value(fromKilometersPerHour: 36) == 36)
        #expect(WindSpeedUnit.ms.value(fromKilometersPerHour: 36) == 10)
        #expect(abs(WindSpeedUnit.mph.value(fromKilometersPerHour: 1.609344) - 1) < 1e-9)
        #expect(abs(WindSpeedUnit.kn.value(fromKilometersPerHour: 1.852) - 1) < 1e-9)
        #expect(WindSpeedUnit.bft.value(fromKilometersPerHour: 50) == 7)
    }

    @Test
    func precipitationPressureAndDistanceConvertFromMetric() {
        #expect(PrecipitationUnit.inch.value(fromMillimeters: 25.4) == 1)
        #expect(PrecipitationUnit.mm.value(fromMillimeters: 2.5) == 2.5)
        #expect(PrecipitationUnit.inch.snow(fromCentimeters: 2.54) == 1)
        #expect(abs(PressureUnit.inhg.value(fromHectopascals: 1013.25) - 29.92) < 0.01)
        #expect(abs(PressureUnit.mmhg.value(fromHectopascals: 1013.25) - 760) < 0.1)
        #expect(abs(DistanceUnit.mi.value(fromKilometers: 1.609344) - 1) < 1e-9)
        #expect(abs(DistanceUnit.mi.area(fromSquareKilometers: 2.589988) - 1) < 1e-6)
    }

    @Test
    func rawValuesStayCompatibleWithStoredSettings() {
        #expect(TemperatureUnit(rawValue: "fahrenheit") == .fahrenheit)
        #expect(WindSpeedUnit(rawValue: "bft") == .bft)
        #expect(PrecipitationUnit(rawValue: "inch") == .inch)
        #expect(PressureUnit(rawValue: "inhg") == .inhg)
        #expect(DistanceUnit(rawValue: "mi") == .mi)
    }

    @Test
    func tinyPrecipitationNeverReadsAsZero() {
        var units = Units.metric
        units.precipitation = .inch
        #expect(units.precipitationNumber(0.1).hasPrefix("<"))
        #expect(!units.precipitationNumber(0).hasPrefix("<"))
        #expect(!units.precipitationNumber(25.4).hasPrefix("<"))
        #expect(Units.metric.precipitationNumber(0.04).hasPrefix("<"))
        #expect(PrecipitationUnit.inch.symbol == "in")
        #expect(WindSpeedUnit.mph.symbol == "mph")
    }

    @Test
    func symbolsAreNeverEmpty() {
        #expect(WindSpeedUnit.allCases.allSatisfy { !$0.symbol.isEmpty })
        #expect(PrecipitationUnit.allCases.allSatisfy { !$0.symbol.isEmpty && !$0.snowSymbol.isEmpty })
        #expect(PressureUnit.allCases.allSatisfy { !$0.symbol.isEmpty })
        #expect(DistanceUnit.allCases.allSatisfy { !$0.symbol.isEmpty && !$0.areaSymbol.isEmpty })
    }
}

struct BeaufortScaleTests {
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
}
