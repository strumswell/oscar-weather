//
//  HourlyFormattingTests.swift
//  Oscar°Tests
//
//  Pure-logic tests for the hourly label formatting.
//

import Foundation
import Testing
@testable import Oscar_

struct HourlyFormattingTests {
    @Test
    func sharedHourSuffixIsWrittenOnce() {
        #expect(HourlyFormatting.joinedHourRange(from: "14 Uhr", to: "17 Uhr") == "14–17 Uhr")
        // 12-hour system formats separate hour and AM/PM with a narrow
        // no-break space (U+202F), not a plain one.
        #expect(HourlyFormatting.joinedHourRange(from: "2\u{202F}PM", to: "5\u{202F}PM") == "2–5\u{202F}PM")
    }

    @Test
    func differingSuffixesStayVerbatim() {
        #expect(HourlyFormatting.joinedHourRange(from: "11\u{202F}AM", to: "2\u{202F}PM") == "11\u{202F}AM–2\u{202F}PM")
    }

    @Test
    func suffixFreeHoursJoinPlainly() {
        #expect(HourlyFormatting.joinedHourRange(from: "14", to: "17") == "14–17")
    }
}
