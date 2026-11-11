import Foundation

enum HourlyFormatting {
  static func hourString(timestamp: Double, timeZone: TimeZone) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))

    if SettingService.resolvedTimeFormatPreference == .h24 {
      return "\(SettingService.formattedTime(date, timeZone: timeZone, showsMinutes: false)) \(String(localized: "Uhr"))"
        .trimmingCharacters(in: .whitespaces)
    }

    return SettingService.formattedTime(date, timeZone: timeZone, showsMinutes: false)
  }

  static func timeString(timestamp: Double, timeZone: TimeZone) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))

    return SettingService.formattedTime(date, timeZone: timeZone)
  }

  static func weekdayString(timestamp: Double, timeZone: TimeZone) -> String {
    SettingService.formattedShortWeekday(
      Date(timeIntervalSince1970: TimeInterval(timestamp)),
      timeZone: timeZone
    )
  }

  static func dayLabel(timestamp: Double, timeZone: TimeZone, now: Date) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    var calendar = Calendar.current
    calendar.timeZone = timeZone

    if calendar.isDate(date, inSameDayAs: now) {
      return String(localized: "Heute")
    }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
       calendar.isDate(date, inSameDayAs: tomorrow) {
      return String(localized: "Morgen")
    }
    return SettingService.formattedWeekday(date, timeZone: timeZone)
  }

  static func weatherIconName(weatherCode: Double, isDay: Double) -> String {
    let base: String
    switch weatherCode {
    case 0, 1:
      base = "01"
    case 2:
      base = "02"
    case 3:
      base = "04"
    case 45, 48:
      base = "50"
    case 51:
      base = "10"
    case 71, 73, 75, 77, 85, 86:
      base = "13"
    case 95, 96, 99:
      base = "11"
    default:
      base = "09"
    }
    return base + (isDay > 0 ? "d" : "n")
  }
}
