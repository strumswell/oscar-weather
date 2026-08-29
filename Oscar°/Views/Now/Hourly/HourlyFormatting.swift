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

  /// Hour span like "14–17 Uhr" or "2–5 PM": a suffix both hours share
  /// ("Uhr", "PM") is written once.
  static func hourRangeString(start: Double, end: Double, timeZone: TimeZone) -> String {
    joinedHourRange(
      from: hourString(timestamp: start, timeZone: timeZone),
      to: hourString(timestamp: end, timeZone: timeZone)
    )
  }

  /// Splits on any whitespace: 12-hour system formats separate "2 PM" with a
  /// narrow no-break space, not a plain one.
  static func joinedHourRange(from: String, to: String) -> String {
    let fromParts = from.split(whereSeparator: \.isWhitespace)
    let toParts = to.split(whereSeparator: \.isWhitespace)
    if fromParts.count > 1, fromParts.last == toParts.last {
      return fromParts.dropLast().joined(separator: " ") + "–" + to
    }
    return from + "–" + to
  }

  /// Beaufort shows force + "Bft"; every other unit the rounded speed in the
  /// unit the API delivered.
  static func windString(_ value: Double, unit: WindSpeedUnit, unitString: String) -> String {
    if unit.usesBeaufortDisplay {
      return "\(BeaufortScale.force(forKilometersPerHour: value)) \(unit.displayUnit)"
    }
    return "\(Int(value.rounded())) \(unitString)"
  }

  static func timeString(timestamp: Double, timeZone: TimeZone) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))

    return SettingService.formattedTime(date, timeZone: timeZone)
  }

  /// Short weekday ("Do", "Fri") for the sun-event cards, which share the
  /// narrow hourly-card width.
  static func weekdayString(timestamp: Double, timeZone: TimeZone) -> String {
    SettingService.formattedShortWeekday(
      Date(timeIntervalSince1970: TimeInterval(timestamp)),
      timeZone: timeZone
    )
  }

  /// Day label for the hourly strip's scroll indicator: "Heute"/"Morgen" for the first
  /// two days, then the full, locale-aware weekday name ("Montag", "Dienstag", …).
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

  static func temperatureString(_ temperature: Double?) -> String {
    guard let temperature else {
      return ""
    }

    return "\(Int(temperature.rounded()))°"
  }

  static func precipitationString(value: Double, unit: String) -> String {
    "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
  }

  static func weatherIconName(weatherCode: Double, isDay: Double) -> String {
    if isDay > 0 {
      switch weatherCode {
      case 0, 1:
        return "01d"
      case 2:
        return "02d"
      case 3:
        return "04d"
      case 45, 48:
        return "50d"
      case 51:
        return "10d"
      case 71, 73, 75, 77, 85, 86:
        return "13d"
      case 95, 96, 99:
        return "11d"
      default:
        return "09d"
      }
    } else {
      switch weatherCode {
      case 0, 1:
        return "01n"
      case 2:
        return "02n"
      case 3:
        return "04n"
      case 45, 48:
        return "50n"
      case 51:
        return "10n"
      case 71, 73, 75, 77, 85, 86:
        return "13n"
      case 95, 96, 99:
        return "11n"
      default:
        return "09n"
      }
    }
  }
}
