//
//  ChapterEngineTests.swift
//  Oscar°Tests
//
//  Pure-logic tests for the hourly chapter segmentation.
//

import Foundation
import Testing
@testable import Oscar_

struct ChapterEngineTests {
    /// 48 hours starting at a fixed midnight UTC; all series default to a calm,
    /// mild, overcast-free day so individual tests only perturb what they test.
    private static let start: Double = 1_754_956_800  // a fixed midnight UTC (2025-08-12)
    private static let hours = 48

    private func makeInput(
        temperature: [Double]? = nil,
        precipitation: [Double]? = nil,
        snowfall: [Double]? = nil,
        weathercode: [Double]? = nil,
        windgusts: [Double]? = nil,
        cloudcover: [Double]? = nil,
        pressure: [Double]? = nil,
        now: Double = ChapterEngineTests.start
    ) -> ChapterEngine.Input {
        let count = Self.hours
        let times = (0..<count).map { Self.start + Double($0) * 3_600 }
        // Day between 06:00 and 20:00 local (UTC here).
        let isDay = (0..<count).map { Double(($0 % 24) >= 6 && ($0 % 24) < 20 ? 1 : 0) }
        return ChapterEngine.Input(
            times: times,
            temperature: temperature ?? Array(repeating: 18, count: count),
            precipitation: precipitation ?? Array(repeating: 0, count: count),
            snowfall: snowfall ?? Array(repeating: 0, count: count),
            weathercode: weathercode ?? Array(repeating: 1, count: count),
            windgusts: windgusts ?? Array(repeating: 20, count: count),
            cloudcover: cloudcover ?? Array(repeating: 10, count: count),
            pressure: pressure ?? Array(repeating: 1015, count: count),
            isDay: isDay,
            timeZone: TimeZone(identifier: "UTC")!,
            now: now,
            precipitationUnit: "mm",
            windUnitString: "km/h",
            windSpeedUnit: .kmh
        )
    }

    @Test
    func rainEventMergesAcrossOneDryHour() {
        var precip = Array(repeating: 0.0, count: Self.hours)
        precip[10] = 1.2
        precip[11] = 2.0
        // Hour 12 dry — must still be one event.
        precip[13] = 0.8
        let chapters = ChapterEngine.chapters(from: makeInput(precipitation: precip))
        let rain = chapters.filter { $0.kind == .precipitation }
        #expect(rain.count == 1)
        #expect(rain.first?.range.lowerBound == Self.start + 10 * 3_600)
        #expect(rain.first?.range.upperBound == Self.start + 14 * 3_600)
        // Jump lands on the peak hour.
        #expect(rain.first?.jumpTime == Self.start + 11 * 3_600)
    }

    @Test
    func twoDryHoursSplitRainEvents() {
        var precip = Array(repeating: 0.0, count: Self.hours)
        precip[10] = 1.0
        precip[14] = 1.0
        let chapters = ChapterEngine.chapters(from: makeInput(precipitation: precip))
        #expect(chapters.filter { $0.kind == .precipitation }.count == 2)
    }

    @Test
    func thunderCodeWinsTheEventTitle() {
        var precip = Array(repeating: 0.0, count: Self.hours)
        var codes = Array(repeating: 1.0, count: Self.hours)
        precip[15] = 3.0
        precip[16] = 5.0
        codes[16] = 95
        let chapters = ChapterEngine.chapters(from: makeInput(precipitation: precip, weathercode: codes))
        let event = chapters.first { $0.kind == .precipitation }
        #expect(event?.systemImage == "cloud.bolt.rain.fill")
    }

    @Test
    func gustWindowNeedsTwoSustainedHours() {
        var gusts = Array(repeating: 20.0, count: Self.hours)
        gusts[8] = 55  // lone spike: no chapter
        let none = ChapterEngine.chapters(from: makeInput(windgusts: gusts))
        #expect(!none.contains { $0.kind == .wind })

        gusts[9] = 60
        gusts[10] = 52
        let some = ChapterEngine.chapters(from: makeInput(windgusts: gusts))
        let wind = some.first { $0.kind == .wind }
        #expect(wind != nil)
        #expect(wind?.jumpTime == Self.start + 9 * 3_600)
        #expect(wind?.subtitle.contains("60") == true)
    }

    @Test
    func clearNightDetectedOnlyWhenClearAndDry() {
        // Baseline: cloudcover 10, no precip → the 20:00–06:00 night qualifies.
        let clear = ChapterEngine.chapters(from: makeInput())
        #expect(clear.contains { $0.kind == .clearNight })

        let cloudy = ChapterEngine.chapters(
            from: makeInput(cloudcover: Array(repeating: 80, count: Self.hours))
        )
        #expect(!cloudy.contains { $0.kind == .clearNight })
    }

    @Test
    func everyDayGetsASummaryChapterAndPastChaptersDrop() {
        // now sits mid-day-one: day one still present (its range ends later),
        // and both days carry summaries.
        let chapters = ChapterEngine.chapters(from: makeInput(now: Self.start + 12 * 3_600))
        let days = chapters.filter { $0.kind == .day }
        #expect(days.count == 2)
        #expect(chapters.allSatisfy { $0.range.upperBound > Self.start + 12 * 3_600 })
        // Sorted by range start.
        let starts = chapters.map(\.range.lowerBound)
        #expect(starts == starts.sorted())
    }

    @Test
    func pressureFallAnnotatesTheDay() {
        var pressure = Array(repeating: 1015.0, count: Self.hours)
        for hour in 6...18 {
            pressure[hour] = 1015 - Double(hour - 6)  // 12 hPa over 12 h
        }
        let chapters = ChapterEngine.chapters(from: makeInput(pressure: pressure))
        let day = chapters.first { $0.kind == .day }
        #expect(day?.subtitle.contains(String(localized: "Druck fällt")) == true)
    }

    @Test
    func daySummaryCarriesDominantConditionAndHigh() {
        var temps = Array(repeating: 15.0, count: Self.hours)
        temps[14] = 27.4
        let chapters = ChapterEngine.chapters(from: makeInput(temperature: temps))
        let day = chapters.first { $0.kind == .day }
        #expect(day?.subtitle.contains("27°") == true)
    }
}
