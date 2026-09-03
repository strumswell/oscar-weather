import Foundation
import SwiftUI

extension Binding where Value == Date? {
    /// Wraps a `.chartXSelection` binding so the continuous drag samples only
    /// invalidate SwiftUI when the selection reaches a different data step.
    /// The cursor and tooltip resolve to the nearest hour anyway, so the
    /// per-sample writes (60–120 Hz) re-rendered the entire chart for
    /// identical output — that was the scrub lag.
    static func snapped(to interval: TimeInterval, _ source: Binding<Date?>) -> Binding<Date?> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in
                let snapped = newValue.map { date in
                    Date(timeIntervalSince1970: (date.timeIntervalSince1970 / interval).rounded() * interval)
                }
                if snapped != source.wrappedValue {
                    source.wrappedValue = snapped
                }
            }
        )
    }
}

enum HourlyChartUtilities {
    static func dayChangeIndices(time: [Double], calendar: Calendar = .current) -> [Int] {
        guard time.count > 1 else { return [] }

        return time.indices.dropFirst().filter { index in
            let previousDate = Date(timeIntervalSince1970: time[index - 1])
            let currentDate = Date(timeIntervalSince1970: time[index])
            return !calendar.isDate(previousDate, inSameDayAs: currentDate)
        }
    }

    static func dayAbbreviation(from date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    static func hourString(from date: Date) -> String {
        SettingService.formattedTime(date, showsMinutes: false)
    }
}
