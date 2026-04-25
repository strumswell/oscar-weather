import Foundation

enum HourlyChartUtilities {
    static func dayChangeIndices(time: [Double], calendar: Calendar = .current) -> [Int] {
        guard time.count > 1 else { return [] }

        return time.indices.dropFirst().filter { index in
            let previousDate = Date(timeIntervalSince1970: time[index - 1])
            let currentDate = Date(timeIntervalSince1970: time[index])
            return !calendar.isDate(previousDate, inSameDayAs: currentDate)
        }
    }

    static func dayChangeIndices(time: [Date], calendar: Calendar = .current) -> [Int] {
        guard time.count > 1 else { return [] }

        return time.indices.dropFirst().filter { index in
            !calendar.isDate(time[index - 1], inSameDayAs: time[index])
        }
    }

    static func dayAbbreviation(from date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    static func timeString(from date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func ticks(from minValue: Double, to maxValue: Double, count: Int) -> [Double] {
        guard count > 1, minValue != maxValue else { return [minValue] }

        let step = (maxValue - minValue) / Double(count - 1)
        return stride(from: minValue, through: maxValue, by: step).map { $0 }
    }
}

func dayChangeIndices(time: [Double]) -> [Int] {
    HourlyChartUtilities.dayChangeIndices(time: time)
}

func dayAbbreviation(from date: Date) -> String {
    HourlyChartUtilities.dayAbbreviation(from: date)
}
