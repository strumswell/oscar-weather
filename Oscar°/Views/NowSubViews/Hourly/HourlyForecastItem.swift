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
}

struct HourlyForecastItem: Identifiable {
  let timestamp: Double
  let hour: String
  let precipitation: String
  let iconName: String
  let temperature: String

  var id: String {
    "forecast-\(timestamp)"
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
