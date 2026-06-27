//
//  WeatherLoadingQueryTests.swift
//  Oscar°Tests
//
//  Pure-logic tests for the loading-query ordering used to track in-flight refresh work.
//

import Testing
@testable import Oscar_

struct WeatherLoadingQueryTests {
    @Test
    func sortOrderFollowsDeclarationOrder() {
        let shuffled: [WeatherLoadingQuery] = [.alerts, .rainRadar, .forecast, .airQuality]
        #expect(shuffled.sorted() == [.forecast, .airQuality, .rainRadar, .alerts])
    }

    @Test
    func comparablePairsAreOrdered() {
        #expect(WeatherLoadingQuery.forecast < .airQuality)
        #expect(WeatherLoadingQuery.airQuality < .rainRadar)
        #expect(WeatherLoadingQuery.rainRadar < .alerts)
    }

    @Test
    func everyCaseHasADisplayName() {
        for query in WeatherLoadingQuery.allCases {
            #expect(!query.displayName.isEmpty)
        }
    }
}
