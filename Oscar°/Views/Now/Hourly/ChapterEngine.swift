import Foundation

/// Segments the hourly forecast into tappable "chapters" — the story layer of
/// the hourly detail sheet: precipitation events, gust windows, clear nights, and a
/// summary chapter per day. Pure and synchronous, unit-tested against synthetic
/// series.
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
    }

    struct Chapter: Identifiable, Equatable {
        enum Kind: Equatable {
            case precipitation
            case wind
            case clearNight
            case day
        }

        let id: String
        let kind: Kind
        /// Chip-highlight range; day chapters span their whole day, so the
        /// narrowest containing range decides the active chip.
        let range: ClosedRange<Double>
        /// Where tapping the chip glides the scrub (an event's peak, a night's
        /// middle, a day's afternoon).
        let jumpTime: Double
        let title: String
        let subtitle: String
        let systemImage: String
    }

    static func chapters(from input: Input) -> [Chapter] {
        guard input.times.count > 1 else { return [] }

        var chapters = precipitationChapters(input)
            + windChapters(input)
            + clearNightChapters(input)
            + dayChapters(input)
        chapters.removeAll { $0.range.upperBound <= input.now }
        chapters.sort { $0.range.lowerBound < $1.range.lowerBound }
        // Keep the chip row scannable; the far tail of 14 days is reachable by
        // panning the strip anyway.
        if chapters.count > 16 {
            chapters.removeLast(chapters.count - 16)
        }
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
                icon = "cloud.heavy.rain.fill"
            } else {
                title = String(localized: "Regen")
                icon = "cloud.rain.fill"
            }

            let peakIndex = run.max { precip[$0] < precip[$1] } ?? run.lowerBound
            let start = input.times[run.lowerBound]
            let end = input.times[run.upperBound] + 3_600
            let subtitle = HourlyFormatting.hourString(timestamp: start, timeZone: input.timeZone)
                + " · " + HourlyFormatting.precipitationString(value: total, unit: input.precipitationUnit)
            return Chapter(
                id: "precip-\(Int(start))",
                kind: .precipitation,
                range: start...end,
                jumpTime: input.times[peakIndex],
                title: title,
                subtitle: subtitle,
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
            let peak = gusts[peakIndex]
            let peakString = input.windSpeedUnit.usesBeaufortDisplay
                ? "\(BeaufortScale.force(forKilometersPerHour: peak)) \(input.windSpeedUnit.displayUnit)"
                : "\(Int(peak.rounded())) \(input.windUnitString)"
            let start = input.times[run.lowerBound]
            let end = input.times[run.upperBound] + 3_600
            return Chapter(
                id: "wind-\(Int(start))",
                kind: .wind,
                range: start...end,
                jumpTime: input.times[peakIndex],
                title: String(localized: "Böiger Wind"),
                subtitle: String(localized: "Böen") + " · " + peakString,
                systemImage: "wind"
            )
        }
    }

    // MARK: - Clear nights

    private static func clearNightChapters(_ input: Input) -> [Chapter] {
        let isDay = input.isDay
        let count = min(input.times.count, isDay.count)
        guard count > 0 else { return [] }

        return runs(count: count, allowGap: 0, where: { isDay[$0] < 0.5 }).compactMap { run in
            guard run.count >= 5 else { return nil }
            let precipTotal = run.reduce(0.0) { $0 + (value(input.precipitation, at: $1) ?? 0) }
            guard precipTotal < 0.1 else { return nil }
            let clouds = run.compactMap { value(input.cloudcover, at: $0) }
            guard !clouds.isEmpty, clouds.reduce(0, +) / Double(clouds.count) < 30 else { return nil }

            let lowTemp = run.compactMap { value(input.temperature, at: $0) }.min()
            let start = input.times[run.lowerBound]
            let end = input.times[run.upperBound] + 3_600
            let middle = input.times[run.lowerBound + run.count / 2]
            let subtitle = String(localized: "Tief") + " "
                + HourlyFormatting.temperatureString(lowTemp)
            return Chapter(
                id: "night-\(Int(start))",
                kind: .clearNight,
                range: start...end,
                jumpTime: middle,
                title: String(localized: "Klare Nacht"),
                subtitle: subtitle,
                systemImage: "moon.stars.fill"
            )
        }
    }

    // MARK: - Day summaries

    private static func dayChapters(_ input: Input) -> [Chapter] {
        var calendar = Calendar.current
        calendar.timeZone = input.timeZone

        var chapters: [Chapter] = []
        var index = 0
        while index < input.times.count {
            let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: input.times[index]))
            var next = index
            while next < input.times.count,
                  calendar.isDate(Date(timeIntervalSince1970: input.times[next]), inSameDayAs: dayStart) {
                next += 1
            }
            defer { index = next }
            let dayIndices = index..<next
            guard dayIndices.count >= 6 else { continue }

            // Condition from the most frequent daytime code (fall back to all
            // hours on the polar-night edge case of no daytime slots).
            var daytime = dayIndices.filter { (value(input.isDay, at: $0) ?? 1) > 0.5 }
            if daytime.isEmpty { daytime = Array(dayIndices) }
            let codes = daytime.compactMap { value(input.weathercode, at: $0).map(Int.init) }
            let dominantCode = codes.reduce(into: [:]) { $0[$1, default: 0] += 1 }
                .max { $0.value < $1.value }?.key ?? 0

            let highTemp = dayIndices.compactMap { value(input.temperature, at: $0) }.max()
            var subtitle = WeatherConditionLabel.text(for: dominantCode)
            if let highTemp {
                subtitle += " · ↑" + HourlyFormatting.temperatureString(highTemp)
            }
            if pressureFalls(input, over: dayIndices) {
                subtitle += " · " + String(localized: "Druck fällt")
            }

            // Jump into the afternoon (or the next full hour when the
            // afternoon has already passed today).
            let afternoon = dayStart.addingTimeInterval(14 * 3_600).timeIntervalSince1970
            let jump = min(max(afternoon, input.now, input.times[dayIndices.lowerBound]),
                           input.times[dayIndices.upperBound - 1])

            chapters.append(Chapter(
                id: "day-\(Int(dayStart.timeIntervalSince1970))",
                kind: .day,
                range: input.times[dayIndices.lowerBound]...(input.times[dayIndices.upperBound - 1] + 3_600),
                jumpTime: jump,
                title: HourlyFormatting.dayLabel(
                    timestamp: input.times[dayIndices.lowerBound],
                    timeZone: input.timeZone,
                    now: Date(timeIntervalSince1970: input.now)
                ),
                subtitle: subtitle,
                systemImage: daySymbol(for: dominantCode)
            ))
        }
        return chapters
    }

    /// ≥ 6 hPa loss inside 12 h anywhere in the day — the classic "weather is
    /// coming" signal.
    private static func pressureFalls(_ input: Input, over indices: Range<Int>) -> Bool {
        for start in indices {
            let end = start + 12
            guard end < input.pressure.count, end < input.times.count else { break }
            if let from = value(input.pressure, at: start),
               let to = value(input.pressure, at: end),
               from - to >= 6 {
                return true
            }
        }
        return false
    }

    private static func daySymbol(for code: Int) -> String {
        switch code {
        case 0, 1: "sun.max.fill"
        case 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 80...82: "cloud.heavy.rain.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    // MARK: - Shared

    /// Contiguous index runs matching a predicate; up to `allowGap` consecutive
    /// non-matching samples inside a run are tolerated (a one-hour pause in the
    /// rain is still the same rain).
    private static func runs(
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
