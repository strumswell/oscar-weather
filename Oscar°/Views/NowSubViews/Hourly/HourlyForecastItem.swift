import Foundation

enum HourlyTimelineItem: Identifiable {
  case forecast(HourlyForecastItem)
  case sunEvent(HourlySunEventItem)

  var id: String {
    switch self {
    case .forecast(let item):
      return item.id
    case .sunEvent(let item):
      return item.id
    }
  }

  var timestamp: Double {
    switch self {
    case .forecast(let item):
      return item.timestamp
    case .sunEvent(let item):
      return item.timestamp
    }
  }
}

struct HourlyForecastItem: Identifiable {
  let timestamp: Double
  let hour: String
  let precipitation: String
  let iconName: String
  let temperature: String
  /// The leading "Jetzt" card carrying live conditions instead of an hourly slot.
  var isNow: Bool = false

  var id: String {
    // A stable id for the now card: its timestamp moves with every refresh, and a
    // changing id would re-create the card instead of animating value changes.
    isNow ? "forecast-now" : "forecast-\(timestamp)"
  }
}

struct HourlySunEventItem: Identifiable {
  enum Kind {
    case sunrise
    case sunset

    var iconName: String {
      switch self {
      case .sunrise:
        return "arrow.up"
      case .sunset:
        return "arrow.down"
      }
    }
  }

  let kind: Kind
  let timestamp: Double
  let time: String
  let weekday: String

  var id: String {
    "sun-\(kind)-\(timestamp)"
  }
}
