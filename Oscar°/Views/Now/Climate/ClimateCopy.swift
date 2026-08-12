//
//  ClimateCopy.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.07.26.
//
import Foundation


// Numbers are pre-formatted into plain strings before being interpolated into the localized
// templates, so years never pick up a locale's grouping separator (e.g. "1.940").
func climateHeadline(_ summary: ClimateSummary) -> String {
    let day = summary.dayLabel
    let year = String(summary.firstYear)
    // A record reads better (and more honestly) as a superlative than "warmer than 100 %".
    if summary.warmerRank == 1 {
        return String(localized: "Der wärmste \(day) seit \(year).")
    }
    if summary.warmerRank == summary.totalYears {
        return String(localized: "Der kälteste \(day) seit \(year).")
    }
    // Clamp to 1…99 so a near-record never rounds to a misleading "0 %"/"100 %".
    let pct = climateHeadlinePercent(min(99, max(1, summary.headlinePercent())))
    if summary.isWarmerThanNormal {
        return String(localized: "Wärmer als \(pct) aller \(day) seit \(year).")
    }
    return String(localized: "Kälter als \(pct) aller \(day) seit \(year).")
}

/// The analog year shown in the copy: the most recent past year whose high *displays the same
/// whole number* as today, so it visibly matches today's shown temperature. (Matching on the
/// rounded display value — not a fixed °C window — is why this lives here, where the unit is
/// known.) Falls back to the nearest by actual value, most recent on ties, when nothing rounds
/// the same.
func climateAnalog(_ summary: ClimateSummary, _ unit: ClimateTemperatureUnit) -> (year: Int, value: Double)? {
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

func climateAnalogLine(_ summary: ClimateSummary, _ unit: ClimateTemperatureUnit) -> String? {
    let day = summary.dayLabel
    let firstYear = String(summary.firstYear)
    // Today is the warmest/coldest on record — there is no genuine analog, so don't fall back to a
    // not-actually-similar year (which would contradict today's own value).
    if summary.warmerRank == 1 {
        return String(localized: "So warm wie heute war es seit \(firstYear) noch nie.")
    }
    if summary.warmerRank == summary.totalYears {
        return String(localized: "So kühl wie heute war es seit \(firstYear) noch nie.")
    }
    guard let analog = climateAnalog(summary, unit) else { return nil }
    let year = String(analog.year)
    let value = "\(Int(unit.value(fromCelsius: analog.value).rounded()))°"
    if summary.isWarmerThanNormal {
        return String(localized: "So warm war ein \(day) zuletzt \(year) (\(value)).")
    }
    return String(localized: "So kühl war ein \(day) zuletzt \(year) (\(value)).")
}

/// Where today falls in the all-time ranking, framed from whichever end is more striking. The
/// number is dropped when today is the outright record.
func climateRankLine(_ summary: ClimateSummary) -> String {
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

func climateStatLine(_ summary: ClimateSummary, _ unit: ClimateTemperatureUnit) -> String {
    let today = summary.anomalyString(unit)
    let normal = summary.normalString(unit)
    let record = summary.previousWarmRecordString(unit)
    let year = String(summary.previousWarmRecord.year)
    return String(localized: "Heute \(today) · Normal \(normal) · Rekord \(record) (\(year))")
}

/// The "X von Y" value next to the heat/frost rows.
///
/// Turkish phrases this as a possessive ("30 yılın 5'i" = "5 of the 30 years"), and that suffix
/// follows the vowel harmony of how the *count* is spoken — so it can't be baked into the string
/// catalog. We attach it to the count here, before substitution.
func climateYearCount(_ count: Int, of total: Int) -> String {
    let countText: String
    if Locale.current.language.languageCode?.identifier == "tr" {
        countText = "\(count)\(turkishPossessiveSuffix(for: count))"
    } else {
        countText = String(count)
    }
    return String(localized: "climate.yearCount",
                  defaultValue: "\(countText) von \(String(total))")
}

/// The percentage fragment of the climate headline ("Wärmer als 65 % …"). Turkish writes the percent
/// in local form and carries an ablative-possessive suffix harmonized to the spoken number
/// ("%65'inden"), so it's assembled here; other languages get the plain "65 %".
private func climateHeadlinePercent(_ percent: Int) -> String {
    if Locale.current.language.languageCode?.identifier == "tr" {
        return "%\(percent)\(turkishAblativePossessiveSuffix(for: percent))"
    }
    return "\(percent) %"
}

/// Turkish ablative-of-possessive suffix ("…'inden") for a digit number, harmonized to its spoken
/// form — e.g. 65 → "'inden", 3 → "'ünden", 6 → "'sından", 30 → "'undan", 40 → "'ından".
private func turkishAblativePossessiveSuffix(for value: Int) -> String {
    let possessive = turkishPossessiveSuffix(for: value)   // "'i" / "'ü" / "'sı" / "'u" / "'ı"
    let isFront = possessive.last == "i" || possessive.last == "ü"
    return "\(possessive)n\(isFront ? "den" : "dan")"
}

/// Turkish 3rd-person possessive suffix (with its leading apostrophe) for a number written as
/// digits — e.g. 5 → "'i" (beş'i), 3 → "'ü" (üç'ü), 6 → "'sı" (altı'sı), 20 → "'si" (yirmi'si).
///
/// The suffix depends only on the last *spoken* word of the number: its final vowel picks one of
/// ı/u/i/ü by vowel harmony (a/ı→ı, o/u→u, e/i→i, ö/ü→ü), and a buffer "s" is inserted when that
/// word ends in a vowel (iki, altı, yedi, yirmi, elli).
private func turkishPossessiveSuffix(for value: Int) -> String {
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
