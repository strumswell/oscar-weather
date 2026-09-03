import Foundation

/// Cached DateFormatters keyed by preference + zone, usable off the main actor
/// (widgets and the watch format on background timelines).
extension SettingService {
    nonisolated private static let formatterLock = NSLock()
    nonisolated(unsafe) private static var formatterCache: [String: DateFormatter] = [:]

    nonisolated static func formattedTime(
        _ date: Date,
        timeZone: TimeZone? = nil,
        showsMinutes: Bool = true
    ) -> String {
        let mode = resolvedTimeFormatPreference
        let key = "time|\(mode.rawValue)|\(showsMinutes)|\(timeZone?.identifier ?? "local")"
        return format(date, key: key) {
            $0.locale = .autoupdatingCurrent
            $0.timeZone = timeZone
            switch mode {
            case .system:
                $0.dateStyle = .none
                $0.timeStyle = showsMinutes ? .short : .none
                if !showsMinutes {
                    $0.dateFormat = DateFormatter.dateFormat(
                        fromTemplate: "j",
                        options: 0,
                        locale: .autoupdatingCurrent
                    )
                }
            case .h24:
                $0.dateFormat = showsMinutes ? "HH:mm" : "HH"
            case .h12:
                $0.dateFormat = showsMinutes ? "h:mm a" : "h a"
            }
        }
    }

    nonisolated static func formattedDateTime(_ date: Date, timeZone: TimeZone? = nil) -> String {
        let key = "date|\(timeZone?.identifier ?? "local")"
        let dateString = format(date, key: key) {
            $0.locale = .autoupdatingCurrent
            $0.timeZone = timeZone
            $0.dateStyle = .short
            $0.timeStyle = .none
        }
        return "\(dateString), \(formattedTime(date, timeZone: timeZone))"
    }

    nonisolated static func formattedWeekday(_ date: Date, timeZone: TimeZone) -> String {
        format(date, key: "weekday|\(timeZone.identifier)") {
            $0.locale = .autoupdatingCurrent
            $0.timeZone = timeZone
            $0.dateFormat = "EEEE"
        }
    }

    nonisolated static func formattedDayMonth(_ date: Date, timeZone: TimeZone) -> String {
        format(date, key: "dayMonth|\(timeZone.identifier)") {
            $0.locale = .autoupdatingCurrent
            $0.timeZone = timeZone
            $0.setLocalizedDateFormatFromTemplate("d MMM")
        }
    }

    nonisolated static func formattedShortWeekday(_ date: Date, timeZone: TimeZone) -> String {
        format(date, key: "shortWeekday|\(timeZone.identifier)") {
            $0.locale = .autoupdatingCurrent
            $0.timeZone = timeZone
            $0.dateFormat = "EEE"
        }
    }

    nonisolated private static func format(
        _ date: Date,
        key: String,
        configure: (DateFormatter) -> Void
    ) -> String {
        formatterLock.withLock {
            let formatter: DateFormatter
            if let cached = formatterCache[key] {
                formatter = cached
            } else {
                formatter = DateFormatter()
                configure(formatter)
                formatterCache[key] = formatter
            }
            return formatter.string(from: date)
        }
    }
}
