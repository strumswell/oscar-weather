import Foundation

/// Segments the forecast into the timeline's chapters: rain events (radar
/// where it has coverage), gust windows, nights, sun events, warnings,
/// pressure falls, and each day's high and low at the hour they happen. Pure
/// and synchronous, unit-tested against synthetic series.
enum ChapterEngine {
    struct Input {
        let times: [Double]
        let temperature: [Double]
        let precipitation: [Double]
        let snowfall: [Double]
        let weathercode: [Double]
        let windgusts: [Double]
        let cloudcover: [Double]
        let pressure: [Double]
        let isDay: [Double]
        let timeZone: TimeZone
        let now: Double
        let precipitationUnit: String
        let windUnitString: String
        let windSpeedUnit: WindSpeedUnit
        var sunrises: [Double] = []
        var sunsets: [Double] = []
        /// Radar series in mm/h, observations + nowcast.
        var radarTimes: [Double] = []
        var radarRates: [Double] = []
        var alertEvents: [AlertEvent] = []
    }

    struct AlertEvent {
        let id: String
        let title: String
        let detail: String?
        let onset: Double?
        let expires: Double?
        let severityRank: Int
        let source: String?
    }

    struct Chapter: Identifiable, Equatable {
        enum Kind: Equatable {
            case precipitation
            case radar
            case wind
            case night
            case sunEvent
            case alert
            case high
            case low
            case pressure
        }

        let id: String
        let kind: Kind
        let range: ClosedRange<Double>
        /// Where tapping the chapter glides the scrub (an event's peak, a
        /// night's middle, a day's afternoon).
        let jumpTime: Double
        let title: String
        /// Time span or annotation under the title; empty hides the line.
        let subtitle: String
        /// Trailing value in the chapter card ("3,2 mm", "Tief 8°"); empty
        /// hides it.
        let valueLabel: String
        let systemImage: String
        var detail: String? = nil
        var severityRank: Int? = nil
        var severitySource: String? = nil
    }

    static func chapters(from input: Input, includingPast: Bool = false) -> [Chapter] {
        guard input.times.count > 1 else { return [] }

        var chapters = precipitationChapters(input)
            + radarChapters(input)
            + windChapters(input)
            + nightChapters(input)
            + sunEventChapters(input)
            + alertChapters(input)
            + pressureChapters(input)
            + extremeChapters(input)
        if let radarStart = input.radarTimes.first,
           let radarEnd = input.radarTimes.last,
           input.radarTimes.count > 2 {
            chapters.removeAll {
                $0.kind == .precipitation
                    && $0.range.lowerBound >= radarStart
                    && $0.range.upperBound <= radarEnd
            }
        }
        if !includingPast {
            chapters.removeAll { $0.range.upperBound <= input.now }
        }
        chapters.sort { $0.range.lowerBound < $1.range.lowerBound }
        return chapters
    }

    // MARK: - Precipitation events

    private static func precipitationChapters(_ input: Input) -> [Chapter] {
        let precip = input.precipitation
        let count = min(input.times.count, precip.count)
        guard count > 0 else { return [] }

        return runs(count: count, allowGap: 1, where: { precip[$0] >= 0.1 }).compactMap { run in
            let total = run.reduce(0.0) { $0 + precip[$1] }
            guard total >= 0.2 else { return nil }

            let snowTotal = run.reduce(0.0) { $0 + (value(input.snowfall, at: $1) ?? 0) }
            let codes = run.compactMap { value(input.weathercode, at: $0).map(Int.init) }
            let title: String
            let icon: String
            if codes.contains(where: { (95...99).contains($0) }) {
                title = String(localized: "Gewitter")
                icon = "cloud.bolt.rain.fill"
            } else if snowTotal > 0.1 {
                title = String(localized: "Schnee")
                icon = "cloud.snow.fill"
            } else if !codes.isEmpty, codes.allSatisfy({ (80...86).contains($0) }) {
                title = String(localized: "Schauer")
                icon = "cloud.heavyrain.fill"
            } else {
                title = String(localized: "Regen")
                icon = "cloud.rain.fill"
            }

            let peakIndex = run.max { precip[$0] < precip[$1] } ?? run.lowerBound
            let start = input.times[run.lowerBound]
            let end = input.times[run.upperBound] + 3_600
            return Chapter(
                id: "precip-\(Int(start))",
                kind: .precipitation,
                range: start...end,
                jumpTime: input.times[peakIndex],
                title: title,
                subtitle: HourlyFormatting.hourRangeString(start: start, end: end, timeZone: input.timeZone),
                valueLabel: HourlyFormatting.precipitationString(value: total, unit: input.precipitationUnit),
                systemImage: icon
            )
        }
    }

    // MARK: - Gust windows

    /// Gust threshold ≈ Beaufort 7 ("Steifer Wind"), expressed in the unit the
    /// API delivered (the arrays already arrive converted).
    private static func gustThreshold(forUnit unit: String) -> Double {
        switch unit {
        case "mph": 31
        case "m/s": 14
        case "kn": 27
        default: 50
        }
    }

    private static func windChapters(_ input: Input) -> [Chapter] {
        let gusts = input.windgusts
        let count = min(input.times.count, gusts.count)
        guard count > 0 else { return [] }
        let threshold = gustThreshold(forUnit: input.windUnitString)

        return runs(count: count, allowGap: 1, where: { gusts[$0] >= threshold }).compactMap { run in
            guard run.count >= 2 else { return nil }
            let peakIndex = run.max { gusts[$0] < gusts[$1] } ?? run.lowerBound
            let peakString = HourlyFormatting.windString(
                gusts[peakIndex], unit: input.windSpeedUnit, unitString: input.windUnitString
            )
            let start = input.times[run.lowerBound]
            let end = input.times[run.upperBound] + 3_600
            return Chapter(
                id: "wind-\(Int(start))",
                kind: .wind,
                range: start...end,
                jumpTime: input.times[peakIndex],
                title: String(localized: "Böiger Wind"),
                subtitle: HourlyFormatting.hourRangeString(start: start, end: end, timeZone: input.timeZone),
                valueLabel: peakString,
                systemImage: "wind"
            )
        }
    }

    // MARK: - Nights

    private static func nightChapters(_ input: Input) -> [Chapter] {
        let isDay = input.isDay
        let count = min(input.times.count, isDay.count)
        guard count > 0 else { return [] }

        return runs(count: count, allowGap: 0, where: { isDay[$0] < 0.5 }).compactMap { run in
            guard run.count >= 5 else { return nil }
            let precipTotal = run.reduce(0.0) { $0 + (value(input.precipitation, at: $1) ?? 0) }
            let clouds = run.compactMap { value(input.cloudcover, at: $0) }
            let meanCloud = clouds.isEmpty ? 100 : clouds.reduce(0, +) / Double(clouds.count)
            let isClear = precipTotal < 0.1 && meanCloud < 30

            let lowTemp = run.compactMap { value(input.temperature, at: $0) }.min()
            let start = input.times[run.lowerBound]
            let end = input.times[run.upperBound] + 3_600
            let middle = input.times[run.lowerBound + run.count / 2]
            return Chapter(
                id: "night-\(Int(start))",
                kind: .night,
                range: start...end,
                jumpTime: middle,
                title: isClear ? String(localized: "Klare Nacht") : String(localized: "Nacht"),
                subtitle: HourlyFormatting.hourRangeString(start: start, end: end, timeZone: input.timeZone),
                valueLabel: String(localized: "Tief") + " " + HourlyFormatting.temperatureString(lowTemp),
                systemImage: isClear ? "moon.stars.fill" : "cloud.moon.fill"
            )
        }
    }

    // MARK: - Sun events

    private static func sunEventChapters(_ input: Input) -> [Chapter] {
        guard let first = input.times.first, let last = input.times.last else { return [] }
        let events = input.sunrises.map { (time: $0, isRise: true) }
            + input.sunsets.map { (time: $0, isRise: false) }
        return events.filter { $0.time >= first && $0.time <= last }.map { event in
            Chapter(
                id: "\(event.isRise ? "sunrise" : "sunset")-\(Int(event.time))",
                kind: .sunEvent,
                range: event.time...event.time,
                jumpTime: event.time,
                title: event.isRise
                    ? String(localized: "Sonnenaufgang")
                    : String(localized: "Sonnenuntergang"),
                subtitle: HourlyFormatting.timeString(timestamp: event.time, timeZone: input.timeZone),
                valueLabel: "",
                systemImage: event.isRise ? "sunrise.fill" : "sunset.fill"
            )
        }
    }

    // MARK: - Radar events

    private static func radarChapters(_ input: Input) -> [Chapter] {
        let times = input.radarTimes
        let rates = input.radarRates
        let count = min(times.count, rates.count)
        guard count > 2 else { return [] }
        let step = max(times[1] - times[0], 60)

        return runs(count: count, allowGap: 2, where: { rates[$0] >= 0.1 }).compactMap { run in
            let peakIndex = run.max { rates[$0] < rates[$1] } ?? run.lowerBound
            guard rates[peakIndex] >= 0.1 else { return nil }
            let start = times[run.lowerBound]
            let end = times[run.upperBound] + step
            let peak = HourlyFormatting.displayRate(fromMillimeters: rates[peakIndex], unit: input.precipitationUnit)
            return Chapter(
                id: "radar-\(Int(start))",
                kind: .radar,
                range: start...end,
                jumpTime: times[peakIndex],
                title: String(localized: "Regen"),
                subtitle: String(localized: "Radar") + " · "
                    + HourlyFormatting.timeString(timestamp: start, timeZone: input.timeZone)
                    + "–"
                    + HourlyFormatting.timeString(timestamp: end, timeZone: input.timeZone),
                valueLabel: "\(peak.formatted(.number.precision(.fractionLength(1)))) \(input.precipitationUnit)/h",
                systemImage: "cloud.rain.fill"
            )
        }
    }

    // MARK: - Weather alerts

    private static func alertChapters(_ input: Input) -> [Chapter] {
        guard let first = input.times.first, let last = input.times.last else { return [] }
        return input.alertEvents.compactMap { event in
            let start = event.onset ?? input.now
            let end = event.expires ?? min(start + 6 * 3_600, last)
            guard end > input.now, start <= last else { return nil }
            let lower = max(min(start, last), first)
            let upper = max(min(end, last + 3_600), lower + 60)
            return Chapter(
                id: "alert-\(event.id)",
                kind: .alert,
                range: lower...upper,
                jumpTime: min(max(start, input.now), last),
                title: event.title,
                subtitle: alertRangeString(
                    onset: event.onset, expires: event.expires, timeZone: input.timeZone
                ),
                valueLabel: "",
                systemImage: "exclamationmark.triangle.fill",
                detail: event.detail,
                severityRank: event.severityRank,
                severitySource: event.source
            )
        }
    }

    private static func alertRangeString(onset: Double?, expires: Double?, timeZone: TimeZone) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        func label(_ timestamp: Double, withDay: Bool) -> String {
            let time = HourlyFormatting.timeString(timestamp: timestamp, timeZone: timeZone)
            guard withDay else { return time }
            return HourlyFormatting.weekdayString(timestamp: timestamp, timeZone: timeZone) + " " + time
        }

        switch (onset, expires) {
        case (let onset?, let expires?):
            let sameDay = calendar.isDate(
                Date(timeIntervalSince1970: onset),
                inSameDayAs: Date(timeIntervalSince1970: expires)
            )
            if sameDay {
                return label(onset, withDay: false) + "–" + label(expires, withDay: false)
            }
            return label(onset, withDay: true) + " – " + label(expires, withDay: true)
        case (let onset?, nil):
            return label(onset, withDay: true)
        case (nil, let expires?):
            return "– " + label(expires, withDay: true)
        case (nil, nil):
            return ""
        }
    }

    // MARK: - Daily extremes

    /// The day's high and low as their own cards, each at the hour it
    /// happens, so the timeline reads chronologically instead of opening
    /// every day with a summary.
    private static func extremeChapters(_ input: Input) -> [Chapter] {
        var calendar = Calendar.current
        calendar.timeZone = input.timeZone
        let count = min(input.times.count, input.temperature.count)

        var chapters: [Chapter] = []
        var index = 0
        while index < count {
            let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: input.times[index]))
            var next = index
            while next < count,
                  calendar.isDate(Date(timeIntervalSince1970: input.times[next]), inSameDayAs: dayStart) {
                next += 1
            }
            defer { index = next }
            let day = index..<next
            // Partial edge days would pin both marks on a couple of hours.
            guard day.count >= 6,
                  let high = day.max(by: { input.temperature[$0] < input.temperature[$1] }),
                  let low = day.min(by: { input.temperature[$0] < input.temperature[$1] }),
                  high != low else { continue }

            for (hour, isHigh) in [(high, true), (low, false)] {
                let start = input.times[hour]
                chapters.append(Chapter(
                    id: "\(isHigh ? "high" : "low")-\(Int(start))",
                    kind: isHigh ? .high : .low,
                    range: start...(start + 3_600),
                    jumpTime: start,
                    title: isHigh ? String(localized: "Hoch") : String(localized: "Tief"),
                    subtitle: HourlyFormatting.hourString(timestamp: start, timeZone: input.timeZone),
                    valueLabel: HourlyFormatting.temperatureString(input.temperature[hour]),
                    systemImage: isHigh ? "thermometer.high" : "thermometer.low"
                ))
            }
        }
        return chapters
    }

    // MARK: - Pressure falls

    /// ≥ 6 hPa loss inside 12 h — the classic "weather is coming" signal.
    /// Consecutive falling windows merge into one event spanning the drop.
    private static func pressureChapters(_ input: Input) -> [Chapter] {
        let pressure = input.pressure
        let count = min(input.times.count, pressure.count) - 12
        guard count > 0 else { return [] }
        func drop(_ index: Int) -> Double { pressure[index] - pressure[index + 12] }

        return runs(count: count, allowGap: 2, where: { drop($0) >= 6 }).map { run in
            let steepest = run.max { drop($0) < drop($1) } ?? run.lowerBound
            let start = input.times[run.lowerBound]
            let end = input.times[run.upperBound + 12]
            return Chapter(
                id: "pressure-\(Int(start))",
                kind: .pressure,
                range: start...end,
                jumpTime: input.times[steepest + 6],
                title: String(localized: "Druck fällt"),
                subtitle: HourlyFormatting.hourRangeString(start: start, end: end, timeZone: input.timeZone),
                valueLabel: "−\(Int(drop(steepest).rounded())) hPa",
                systemImage: "barometer"
            )
        }
    }

    // MARK: - Shared

    /// Contiguous index runs matching a predicate; up to `allowGap` consecutive
    /// non-matching samples inside a run are tolerated (a one-hour pause in the
    /// rain is still the same rain).
    static func runs(
        count: Int,
        allowGap: Int,
        where predicate: (Int) -> Bool
    ) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        var start: Int?
        var lastHit: Int?
        for index in 0..<count {
            if predicate(index) {
                if start == nil { start = index }
                lastHit = index
            } else if let opened = start, let hit = lastHit, index - hit > allowGap {
                result.append(opened...hit)
                start = nil
                lastHit = nil
            }
        }
        if let opened = start, let hit = lastHit {
            result.append(opened...hit)
        }
        return result
    }

    private static func value(_ values: [Double], at index: Int) -> Double? {
        values.indices.contains(index) ? values[index] : nil
    }
}
