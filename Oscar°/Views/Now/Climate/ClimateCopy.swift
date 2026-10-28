//
//  ClimateCopy.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.07.26.
//
import Foundation

enum ClimateCopy {
    static func headline(_ summary: ClimateSummary) -> String {
        let day = summary.dayLabel
        let year = String(summary.firstYear)
        if summary.warmerRank == 1 {
            return String(localized: "Der wärmste \(day) seit \(year).")
        }
        if summary.warmerRank == summary.totalYears {
            return String(localized: "Der kälteste \(day) seit \(year).")
        }
        let pct = headlinePercent(min(99, max(1, summary.headlinePercent())))
        if summary.isWarmerThanNormal {
            return String(localized: "Wärmer als \(pct) aller \(day) seit \(year).")
        }
        return String(localized: "Kälter als \(pct) aller \(day) seit \(year).")
    }

    static func analog(_ summary: ClimateSummary, _ unit: TemperatureUnit) -> (year: Int, value: Double)? {
        guard !summary.pastStripes.isEmpty else { return nil }
        let todayDisplay = Int(unit.value(fromCelsius: summary.todayHigh).rounded())
        let sameDisplay = summary.pastStripes.filter {
            Int(unit.value(fromCelsius: $0.value).rounded()) == todayDisplay
        }
        if let mostRecent = sameDisplay.max(by: { $0.year < $1.year }) {
            return (mostRecent.year, mostRecent.value)
        }
        let nearest = summary.pastStripes.min { lhs, rhs in
            let lhsDistance = abs(lhs.value - summary.todayHigh)
            let rhsDistance = abs(rhs.value - summary.todayHigh)
            return lhsDistance != rhsDistance ? lhsDistance < rhsDistance : lhs.year > rhs.year
        }
        return nearest.map { ($0.year, $0.value) }
    }

    static func analogLine(_ summary: ClimateSummary, _ unit: TemperatureUnit) -> String? {
        let day = summary.dayLabel
        let firstYear = String(summary.firstYear)
        if summary.warmerRank == 1 {
            return String(localized: "So warm wie heute war es seit \(firstYear) noch nie.")
        }
        if summary.warmerRank == summary.totalYears {
            return String(localized: "So kühl wie heute war es seit \(firstYear) noch nie.")
        }
        guard let analog = analog(summary, unit) else { return nil }
        let year = String(analog.year)
        let value = "\(Int(unit.value(fromCelsius: analog.value).rounded()))°"
        if summary.isWarmerThanNormal {
            return String(localized: "So warm war ein \(day) zuletzt \(year) (\(value)).")
        }
        return String(localized: "So kühl war ein \(day) zuletzt \(year) (\(value)).")
    }

    static func rankLine(_ summary: ClimateSummary) -> String {
        let day = summary.dayLabel
        let year = String(summary.firstYear)
        let fromWarm = summary.warmerRank
        let fromCold = summary.totalYears - summary.warmerRank + 1
        if fromWarm == 1 {
            return String(localized: "Das ist der wärmste \(day) seit \(year).")
        }
        if fromCold == 1 {
            return String(localized: "Das ist der kälteste \(day) seit \(year).")
        }
        if fromWarm <= fromCold {
            let rank = String(fromWarm)
            return String(localized: "Das ist der \(rank). wärmste \(day) seit \(year).")
        }
        let rank = String(fromCold)
        return String(localized: "Das ist der \(rank). kälteste \(day) seit \(year).")
    }

    static func statLine(_ summary: ClimateSummary, _ unit: TemperatureUnit) -> String {
        let today = summary.anomalyString(unit)
        let normal = summary.normalString(unit)
        let record = summary.previousWarmRecordString(unit)
        let year = String(summary.previousWarmRecord.year)
        return String(localized: "Heute \(today) · Normal \(normal) · Rekord \(record) (\(year))")
    }

    static func yearCount(_ count: Int, of total: Int) -> String {
        let countText: String
        if Locale.current.language.languageCode?.identifier == "tr" {
            countText = "\(count)\(turkishPossessiveSuffix(for: count))"
        } else {
            countText = String(count)
        }
        return String(localized: "climate.yearCount",
                      defaultValue: "\(countText) von \(String(total))")
    }

    private static func headlinePercent(_ percent: Int) -> String {
        if Locale.current.language.languageCode?.identifier == "tr" {
            return "%\(percent)\(turkishAblativePossessiveSuffix(for: percent))"
        }
        return "\(percent) %"
    }

    private static func turkishAblativePossessiveSuffix(for value: Int) -> String {
        let possessive = turkishPossessiveSuffix(for: value)
        let isFront = possessive.last == "i" || possessive.last == "ü"
        return "\(possessive)n\(isFront ? "den" : "dan")"
    }

    private static func turkishPossessiveSuffix(for value: Int) -> String {
        let units = ["", "i", "si", "ü", "ü", "i", "sı", "si", "i", "u"]   // bir…dokuz
        let tens  = ["", "u", "si", "u", "ı", "si", "ı", "i", "i", "ı"]    // on…doksan

        let n = abs(value)
        let body: String
        if n % 10 != 0 {
            body = units[n % 10]
        } else if (n / 10) % 10 != 0 {
            body = tens[(n / 10) % 10]
        } else if n == 0 {
            body = "ı"                       // sıfır
        } else if n % 1_000 != 0 {
            body = "ü"                       // …yüz
        } else if n % 1_000_000 != 0 {
            body = "i"                       // …bin
        } else if n % 1_000_000_000 != 0 {
            body = "u"                       // …milyon
        } else {
            body = "ı"                       // …milyar
        }
        return "'\(body)"
    }
}
