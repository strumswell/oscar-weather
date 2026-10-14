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

struct ClimateStripe: Identifiable, Sendable {
    let year: Int
    let value: Double
    let anomaly: Double

    var id: Int { year }
}

struct ClimateSummary: Sendable {
    struct Extreme: Sendable {
        let year: Int
        let value: Double
    }

    let dayLabel: String
    let firstYear: Int
    let pastStripes: [ClimateStripe]
    let todayYear: Int
    let todayHigh: Double
    let normal: Double
    let anomaly: Double
    let coolerShare: Double
    let recordMax: Extreme
    let recordMin: Extreme
    let previousWarmRecord: Extreme
    let decadalTrendCelsius: Double?
    let warmerRank: Int
    let totalYears: Int
    let standardDeviation: Double
    let typicalLow: Double
    let typicalHigh: Double
    let hotYears: Int
    let frostYears: Int
    let lastRecordYear: Int
    let lastRecordIsHot: Bool
    let lastRecordValue: Double

    var isWarmerThanNormal: Bool { anomaly >= 0 }

    var todayStripe: ClimateStripe {
        ClimateStripe(year: todayYear, value: todayHigh, anomaly: anomaly)
    }

    var allStripes: [ClimateStripe] { pastStripes + [todayStripe] }
}

// MARK: - Reduction

extension ClimateSummary {
    static func make(
        time: [String],
        tmax: [Double?],
        referenceDate: Date,
        todayOverride: Double? = nil,
        locale: Locale = .autoupdatingCurrent
    ) -> ClimateSummary? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        let reference = calendar.dateComponents([.month, .day], from: referenceDate)
        guard let refMonth = reference.month, let refDay = reference.day else { return nil }

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

        let currentYear = calendar.component(.year, from: referenceDate)
        if let todayOverride {
            perYear.removeAll { $0.year == currentYear }
            perYear.append((year: currentYear, value: todayOverride))
            perYear.sort { $0.year < $1.year }
        }

        guard perYear.count >= 5, let current = perYear.last else { return nil }

        guard current.year == currentYear else { return nil }

        let todayYear = current.year
        let todayHigh = current.value
        let pastYears = perYear.filter { $0.year != todayYear }
        guard !pastYears.isEmpty else { return nil }

        let normalWindow = perYear.filter { (1961...1990).contains($0.year) }
        let normalSource = normalWindow.isEmpty ? pastYears : normalWindow
        let normal = normalSource.reduce(0) { $0 + $1.value } / Double(normalSource.count)
        let anomaly = todayHigh - normal

        let coolerCount = pastYears.filter { $0.value < todayHigh }.count
        let coolerShare = Double(coolerCount) / Double(pastYears.count)

        let recordMax = perYear.max(by: { $0.value < $1.value })!
        let recordMin = perYear.min(by: { $0.value < $1.value })!

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

    func previousWarmRecordString(_ unit: ClimateTemperatureUnit) -> String {
        Self.tempString(previousWarmRecord.value, unit)
    }

    func recordMinString(_ unit: ClimateTemperatureUnit) -> String {
        Self.tempString(recordMin.value, unit)
    }

    func typicalRangeString(_ unit: ClimateTemperatureUnit) -> String {
        let low = Int(unit.value(fromCelsius: typicalLow).rounded())
        let high = Int(unit.value(fromCelsius: typicalHigh).rounded())
        return "\(low)–\(high)°"
    }

    func hotThresholdLabel(_ unit: ClimateTemperatureUnit) -> String {
        "≥ \(Int(unit.value(fromCelsius: 30).rounded()))°"
    }

    func frostThresholdLabel(_ unit: ClimateTemperatureUnit) -> String {
        "< \(Int(unit.value(fromCelsius: 0).rounded()))°"
    }

    func lastRecordString(_ unit: ClimateTemperatureUnit) -> String {
        "\(Self.tempString(lastRecordValue, unit)) · \(lastRecordYear)"
    }

    func trendString(_ unit: ClimateTemperatureUnit) -> String? {
        guard let trend = decadalTrendCelsius else { return nil }
        let value = unit.delta(fromCelsius: trend)
        let formatted = value.formatted(
            .number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
        return String(localized: "\(formatted)°/Jahrzehnt")
    }

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
