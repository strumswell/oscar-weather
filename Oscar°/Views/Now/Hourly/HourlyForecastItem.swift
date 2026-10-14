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
  var isNow: Bool = false
  var precipitationValue: Double = 0

  var id: String {
    isNow ? "forecast-now" : "forecast-\(timestamp)"
  }
}

struct HourlySunEventItem: Identifiable {
  enum Kind {
    case sunrise
    case sunset

    var imageName: String {
      switch self {
      case .sunrise:
        return "sunrise"
      case .sunset:
        return "sunset"
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
