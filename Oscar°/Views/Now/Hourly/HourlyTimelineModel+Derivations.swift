import Foundation

extension HourlyTimelineModel {
    // MARK: - Derived timeline features

    static func nightRanges(times: [Double], isDay: [Double]) -> [ClosedRange<Double>] {
        guard times.count == isDay.count, !times.isEmpty else { return [] }
        var ranges: [ClosedRange<Double>] = []
        var start: Double?
        for (index, flag) in isDay.enumerated() {
            let isNight = flag < 0.5
            if isNight, start == nil {
                start = times[index]
            }
            if !isNight, let opened = start {
                if times[index] > opened {
                    ranges.append(opened...times[index])
                }
                start = nil
            }
        }
        if let opened = start, let last = times.last, last > opened {
            ranges.append(opened...last)
        }
        return ranges
    }

    static func dayMarks(times: [Double], timeZone: TimeZone) -> [DayMark] {
        guard let first = times.first, let last = times.last else { return [] }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let now = Date.now

        var marks: [DayMark] = []
        var dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: first))
        while dayStart.timeIntervalSince1970 <= last {
            let start = max(dayStart.timeIntervalSince1970, first)
            let weekday = HourlyFormatting.weekdayString(
                timestamp: dayStart.timeIntervalSince1970,
                timeZone: timeZone
            )
            let label: String
            let shortLabel: String
            if calendar.isDate(dayStart, inSameDayAs: now) {
                label = String(localized: "Heute")
                shortLabel = label
            } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                      calendar.isDate(dayStart, inSameDayAs: tomorrow) {
                label = String(localized: "Morgen")
                shortLabel = weekday
            } else {
                label = weekday
                shortLabel = weekday
            }
            marks.append(DayMark(
                start: start,
                label: label + " " + SettingService.formattedDayMonth(dayStart, timeZone: timeZone),
                shortLabel: shortLabel
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            dayStart = next
        }
        return marks
    }

    static func dailyExtremes(times: [Double], values: [Double], timeZone: TimeZone) -> [ExtremeMark] {
        guard times.count == values.count, !times.isEmpty else { return [] }
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        var marks: [ExtremeMark] = []
        var index = 0
        while index < times.count {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: times[index]))
            var highIndex = index
            var lowIndex = index
            var next = index
            while next < times.count,
                  calendar.isDate(Date(timeIntervalSince1970: times[next]), inSameDayAs: day) {
                if values[next] > values[highIndex] { highIndex = next }
                if values[next] < values[lowIndex] { lowIndex = next }
                next += 1
            }
            // Partial edge days with only a couple of hours would stack both
            // marks on nearly the same point — skip those.
            if next - index >= 3 {
                marks.append(ExtremeMark(timestamp: times[highIndex], value: values[highIndex], isHigh: true))
                if lowIndex != highIndex {
                    marks.append(ExtremeMark(timestamp: times[lowIndex], value: values[lowIndex], isHigh: false))
                }
            }
            index = next
        }
        return marks
    }
}
