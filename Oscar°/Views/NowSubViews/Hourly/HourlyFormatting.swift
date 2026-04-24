import Foundation

enum HourlyFormatting {
  static func hourString(timestamp: Double, timeZone: TimeZone) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    var calendar = Calendar.current
    calendar.timeZone = timeZone
    let hours = calendar.component(.hour, from: date)

    return String(format: "%02d %@", hours, String(localized: "Uhr"))
      .trimmingCharacters(in: .whitespaces)
  }

  static func timeString(timestamp: Double, timeZone: TimeZone) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    var calendar = Calendar.current
    calendar.timeZone = timeZone
    let hours = calendar.component(.hour, from: date)
    let minutes = calendar.component(.minute, from: date)

    return String(format: "%02d:%02d", hours, minutes)
  }

  static func weekdayString(timestamp: Double, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = timeZone
    formatter.dateFormat = "EEEE"

    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
  }

  static func temperatureString(_ temperature: Double?) -> String {
    guard let temperature else {
      return ""
    }

    return "\(Int(temperature.rounded()))°"
  }

  static func precipitationString(value: Double, unit: String) -> String {
    String(format: "%.1f %@", value, unit)
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
