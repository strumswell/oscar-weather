//
//  ClimateSummary.swift
//  Oscar°
//
//  Glanceable climate context for "this calendar day" at a location, derived entirely from
//  the historical daily-high series. The science (normal, anomaly, records) is computed and
//  stored in °C so the warming-stripes color mapping stays perceptually consistent regardless
//  of the user's unit; the views convert to the display unit only for the numbers they show.
//

import Foundation

/// Display unit for the section. The archive is always fetched in °C; conversions here turn the
/// stored Celsius values into the user's selected unit (absolute temperatures *and* the anomaly,
/// which is a difference and therefore has no offset term).
enum ClimateTemperatureUnit {
    case celsius
    case fahrenheit

    init(settingValue: String) {
        self = settingValue == "fahrenheit" ? .fahrenheit : .celsius
    }

    var symbol: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }

    func value(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius: celsius
        case .fahrenheit: celsius * 9 / 5 + 32
        }
    }

    /// Inverse of `value(fromCelsius:)` — converts a value in this unit back to °C.
    func celsius(fromValue value: Double) -> Double {
        switch self {
        case .celsius: value
        case .fahrenheit: (value - 32) * 5 / 9
        }
    }

    func delta(fromCelsius delta: Double) -> Double {
        switch self {
        case .celsius: delta
        case .fahrenheit: delta * 9 / 5
        }
    }
}

/// One past year's high on the reference calendar day, with its anomaly vs. the
/// #ShowYourStripes reference normal. Drives a single warming-stripe.
struct ClimateStripe: Identifiable, Sendable {
    let year: Int
    /// This-day high for the year, in °C.
    let value: Double
    /// `value − normal`, in °C. Drives the stripe color.
    let anomaly: Double

    var id: Int { year }
}

struct ClimateSummary: Sendable {
    struct Extreme: Sendable {
        let year: Int
        let value: Double
    }

    /// Localized "this day" label, e.g. "28. Juni".
    let dayLabel: String
    /// Earliest year present in the series (≈1940).
    let firstYear: Int
    /// Oldest → newest, one per year *excluding* the current one (the current year is "heute").
    let pastStripes: [ClimateStripe]
    let todayYear: Int
    /// Most recent year's this-day high, in °C.
    let todayHigh: Double
    /// 1961–1990 reference mean, in °C (the blue/red boundary).
    let normal: Double
    /// `todayHigh − normal`, in °C.
    let anomaly: Double
    /// Share of past years cooler than today, 0...1.
    let coolerShare: Double
    let recordMax: Extreme
    let recordMin: Extreme
    /// Warmest year *excluding today* — so a record-breaking today shows the previous record.
    let previousWarmRecord: Extreme
    /// Linear-regression warming rate over the whole series, in °C per decade (nil if too short).
    let decadalTrendCelsius: Double?
    /// Today's rank among all years on this date, 1 = warmest.
    let warmerRank: Int
    /// Number of years in the series (incl. today).
    let totalYears: Int
    /// Reference spread of this-day highs, in °C. Sets the warming-stripes color scale (±3.0σ).
    let standardDeviation: Double
    /// 10th / 90th percentile of this-day highs, in °C — the "usual" range.
    let typicalLow: Double
    let typicalHigh: Double
    /// How many years this day reached ≥ 30 °C / stayed < 0 °C.
    let hotYears: Int
    let frostYears: Int
    /// Most recent year *excluding today* this date set a record — its kind and value (°C).
    let lastRecordYear: Int
    let lastRecordIsHot: Bool
    let lastRecordValue: Double

    var isWarmerThanNormal: Bool { anomaly >= 0 }

    var todayStripe: ClimateStripe {
        ClimateStripe(year: todayYear, value: todayHigh, anomaly: anomaly)
    }

    /// Past years plus today as the final stripe, so the ribbon's right edge shows today's color
    /// rather than a blank cap.
    var allStripes: [ClimateStripe] { pastStripes + [todayStripe] }
}

// MARK: - Reduction

extension ClimateSummary {
    /// Reduces a raw daily-high series ("this calendar day, per year") and derives the headline
    /// statistics. Returns `nil` when too few valid years exist to say anything meaningful.
    static func make(
        time: [String],
        tmax: [Double?],
        referenceDate: Date,
        todayOverride: Double? = nil,
        locale: Locale = .autoupdatingCurrent
    ) -> ClimateSummary? {
        // Use the local zone so "today" — and thus the reference month/day matched below — agrees
        // with the day label and the cache day-string, which are also local.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        let reference = calendar.dateComponents([.month, .day], from: referenceDate)
        guard let refMonth = reference.month, let refDay = reference.day else { return nil }

        // Take the exact calendar day (e.g. every 28 June) for each year — no smoothing window, so
        // every past year and "today" are the same single-day statistic, and the section reads
        // literally as "all the 28 Junes". (ERA5 is gap-free, so the exact day is essentially always
        // present for past years; the current year is supplied via todayOverride below.)
        var sums: [Int: Double] = [:]
        let count = min(time.count, tmax.count)

        for i in 0..<count {
            guard let value = tmax[i] else { continue }
            let parts = time[i].split(separator: "-")
            guard parts.count == 3,
                let year = Int(parts[0]),
                let month = Int(parts[1]),
                let day = Int(parts[2]),
                month == refMonth, day == refDay
            else { continue }
            sums[year] = value
        }

        var perYear = sums
            .map { (year: $0.key, value: $0.value) }
            .sorted { $0.year < $1.year }

        // Overlay this year's live high. ERA5 reanalysis lags ~5 days, so the current year's exact
        // day is usually still missing; without this, "today" silently becomes last year in both
        // the band and every statistic.
        let currentYear = calendar.component(.year, from: referenceDate)
        if let todayOverride {
            perYear.removeAll { $0.year == currentYear }
            perYear.append((year: currentYear, value: todayOverride))
            perYear.sort { $0.year < $1.year }
        }

        guard perYear.count >= 5, let current = perYear.last else { return nil }

        // Only proceed if the most recent point really is this year. With no live value supplied
        // and no current-year ERA5 data yet (offline + lag), the last point would be a prior year —
        // hide the section rather than pass an old year off as "today".
        guard current.year == currentYear else { return nil }

        let todayYear = current.year
        let todayHigh = current.value
        let pastYears = perYear.filter { $0.year != todayYear }
        guard !pastYears.isEmpty else { return nil }

        // Use a historical 1961–1990 normal as the blue/red boundary, so the climate section
        // does not absorb as much recent warming into "normal". Fall back to the
        // full past mean for locations that do not have enough coverage in that window.
        let normalWindow = perYear.filter { (1961...1990).contains($0.year) }
        let normalSource = normalWindow.isEmpty ? pastYears : normalWindow
        let normal = normalSource.reduce(0) { $0 + $1.value } / Double(normalSource.count)
        let anomaly = todayHigh - normal

        let coolerCount = pastYears.filter { $0.value < todayHigh }.count
        let coolerShare = Double(coolerCount) / Double(pastYears.count)

        let recordMax = perYear.max(by: { $0.value < $1.value })!
        let recordMin = perYear.min(by: { $0.value < $1.value })!

        // Warming rate: least-squares slope of value vs. year, scaled to °C per decade.
        let decadalTrend: Double?
        if perYear.count >= 10 {
            let meanYear = perYear.reduce(0.0) { $0 + Double($1.year) } / Double(perYear.count)
            let meanValue = perYear.reduce(0.0) { $0 + $1.value } / Double(perYear.count)
            var covariance = 0.0
            var variance = 0.0
            for point in perYear {
                let dx = Double(point.year) - meanYear
                covariance += dx * (point.value - meanValue)
                variance += dx * dx
            }
            decadalTrend = variance > 0 ? covariance / variance * 10 : nil
        } else {
            decadalTrend = nil
        }

        let warmerRank = perYear.filter { $0.value > todayHigh }.count + 1

        // Spread + usual range. The FAQ scales colors by ±3.0σ over 1901–2000; ERA5
        // starts in 1940, so use the available part of that window and fall back to the full series
        // only if the reference window is too short.
        let allValues = perYear.map { $0.value }
        let scaleWindow = perYear.filter { (1901...2000).contains($0.year) }.map(\.value)
        let scaleValues = scaleWindow.count >= 10 ? scaleWindow : allValues
        let scaleMean = scaleValues.reduce(0, +) / Double(scaleValues.count)
        let variance =
            scaleValues.reduce(0) { $0 + ($1 - scaleMean) * ($1 - scaleMean) }
            / Double(scaleValues.count)
        let standardDeviation = variance.squareRoot()

        let sortedValues = allValues.sorted()
        func percentile(_ fraction: Double) -> Double {
            if sortedValues.count == 1 { return sortedValues[0] }
            let rank = fraction * Double(sortedValues.count - 1)
            let lowerIndex = Int(rank.rounded(.down))
            let upperIndex = Int(rank.rounded(.up))
            let weight = rank - Double(lowerIndex)
            return sortedValues[lowerIndex]
                + (sortedValues[upperIndex] - sortedValues[lowerIndex]) * weight
        }
        let typicalLow = percentile(0.1)
        let typicalHigh = percentile(0.9)
        let hotYears = allValues.filter { $0 >= 30 }.count
        let frostYears = allValues.filter { $0 < 0 }.count

        // Most recent year *excluding today* that this date set a record. Kept separate from
        // recordMax/recordMin (which include today) so "Wärmster: heute" and the previous record
        // can both be shown. The warm record is usually recent in a warming climate, the cold old.
        let pastRecordMax = pastYears.max(by: { $0.value < $1.value })!
        let pastRecordMin = pastYears.min(by: { $0.value < $1.value })!
        let lastRecordIsHot = pastRecordMax.year >= pastRecordMin.year
        let lastRecordYear = lastRecordIsHot ? pastRecordMax.year : pastRecordMin.year
        let lastRecordValue = lastRecordIsHot ? pastRecordMax.value : pastRecordMin.value

        let pastStripes = pastYears.map {
            ClimateStripe(year: $0.year, value: $0.value, anomaly: $0.value - normal)
        }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = locale
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.setLocalizedDateFormatFromTemplate("dMMMM")

        return ClimateSummary(
            dayLabel: dayFormatter.string(from: referenceDate),
            firstYear: perYear.first!.year,
            pastStripes: pastStripes,
            todayYear: todayYear,
            todayHigh: todayHigh,
            normal: normal,
            anomaly: anomaly,
            coolerShare: coolerShare,
            recordMax: Extreme(year: recordMax.year, value: recordMax.value),
            recordMin: Extreme(year: recordMin.year, value: recordMin.value),
            previousWarmRecord: Extreme(year: pastRecordMax.year, value: pastRecordMax.value),
            decadalTrendCelsius: decadalTrend,
            warmerRank: warmerRank,
            totalYears: perYear.count,
            standardDeviation: standardDeviation,
            typicalLow: typicalLow,
            typicalHigh: typicalHigh,
            hotYears: hotYears,
            frostYears: frostYears,
            lastRecordYear: lastRecordYear,
            lastRecordIsHot: lastRecordIsHot,
            lastRecordValue: lastRecordValue
        )
    }
}

// MARK: - Display formatting

extension ClimateSummary {
    /// Percentage used in the headline: the share of years today is warmer than (when above
    /// normal) or colder than (when below), so the sentence always reads naturally.
    func headlinePercent() -> Int {
        let fraction = isWarmerThanNormal ? coolerShare : 1 - coolerShare
        return Int((fraction * 100).rounded())
    }

    func todayHighString(_ unit: ClimateTemperatureUnit) -> String {
        Self.tempString(todayHigh, unit)
    }

    func normalString(_ unit: ClimateTemperatureUnit) -> String {
        Self.tempString(normal, unit)
    }

    func recordMaxString(_ unit: ClimateTemperatureUnit) -> String {
        Self.tempString(recordMax.value, unit)
    }

    /// Previous warm record (excluding today), e.g. "37°".
    func previousWarmRecordString(_ unit: ClimateTemperatureUnit) -> String {
        Self.tempString(previousWarmRecord.value, unit)
    }

    func recordMinString(_ unit: ClimateTemperatureUnit) -> String {
        Self.tempString(recordMin.value, unit)
    }

    /// The "usual" range (10th–90th percentile), e.g. "21–27°".
    func typicalRangeString(_ unit: ClimateTemperatureUnit) -> String {
        let low = Int(unit.value(fromCelsius: typicalLow).rounded())
        let high = Int(unit.value(fromCelsius: typicalHigh).rounded())
        return "\(low)–\(high)°"
    }

    /// Threshold labels for the heat/frost-day stats, in the user's unit (e.g. "≥ 30°", "< 0°").
    func hotThresholdLabel(_ unit: ClimateTemperatureUnit) -> String {
        "≥ \(Int(unit.value(fromCelsius: 30).rounded()))°"
    }

    func frostThresholdLabel(_ unit: ClimateTemperatureUnit) -> String {
        "< \(Int(unit.value(fromCelsius: 0).rounded()))°"
    }

    /// Previous record (excluding today) as "35° · 2023".
    func lastRecordString(_ unit: ClimateTemperatureUnit) -> String {
        "\(Self.tempString(lastRecordValue, unit)) · \(lastRecordYear)"
    }

    /// Signed warming rate, e.g. "+0,3°/Jahrzehnt", or nil when the series is too short.
    func trendString(_ unit: ClimateTemperatureUnit) -> String? {
        guard let trend = decadalTrendCelsius else { return nil }
        let value = unit.delta(fromCelsius: trend)
        let formatted = value.formatted(
            .number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
        return String(localized: "\(formatted)°/Jahrzehnt")
    }

    /// Signed, one-decimal anomaly, e.g. "+2,3°".
    func anomalyString(_ unit: ClimateTemperatureUnit) -> String {
        let value = unit.delta(fromCelsius: anomaly)
        let formatted = value.formatted(
            .number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false))
        )
        return "\(formatted)°"
    }

    private static func tempString(_ celsius: Double, _ unit: ClimateTemperatureUnit) -> String {
        "\(Int(unit.value(fromCelsius: celsius).rounded()))°"
    }
}
