import Foundation

struct DailyEnsembleForecastResponse: Decodable {
  let latitude: Double?
  let longitude: Double?
  let utcOffsetSeconds: Int?
  let timezone: String?
  let timezoneAbbreviation: String?
  let dailyUnits: [String: String]
  let daily: DailyEnsembleForecastDaily

  enum CodingKeys: String, CodingKey {
    case latitude
    case longitude
    case utcOffsetSeconds = "utc_offset_seconds"
    case timezone
    case timezoneAbbreviation = "timezone_abbreviation"
    case dailyUnits = "daily_units"
    case daily
  }
}

struct DailyEnsembleForecastDaily: Decodable {
  let time: [String]
  let temperature2mMin: [Double?]
  let temperature2mMax: [Double?]
  let precipitationSum: [Double?]
  let windSpeed10mMin: [Double?]
  let windSpeed10mMax: [Double?]
  let windDirection10mDominant: [Double?]
  let temperature2mMinMembers: [[Double?]]
  let temperature2mMaxMembers: [[Double?]]
  let precipitationSumMembers: [[Double?]]
  let windSpeed10mMinMembers: [[Double?]]
  let windSpeed10mMaxMembers: [[Double?]]
  let windDirection10mDominantMembers: [[Double?]]

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)

    time = try container.decodeStringArray(forKey: "time")
    temperature2mMin = container.decodeOptionalDoubleArray(forKey: "temperature_2m_min")
    temperature2mMax = container.decodeOptionalDoubleArray(forKey: "temperature_2m_max")
    precipitationSum = container.decodeOptionalDoubleArray(forKey: "precipitation_sum")
    windSpeed10mMin = container.decodeOptionalDoubleArray(forKey: "wind_speed_10m_min")
    windSpeed10mMax = container.decodeOptionalDoubleArray(forKey: "wind_speed_10m_max")
    windDirection10mDominant = container.decodeOptionalDoubleArray(
      forKey: "wind_direction_10m_dominant"
    )

    temperature2mMinMembers = container.decodeMemberArrays(prefix: "temperature_2m_min_member")
    temperature2mMaxMembers = container.decodeMemberArrays(prefix: "temperature_2m_max_member")
    precipitationSumMembers = container.decodeMemberArrays(prefix: "precipitation_sum_member")
    windSpeed10mMinMembers = container.decodeMemberArrays(prefix: "wind_speed_10m_min_member")
    windSpeed10mMaxMembers = container.decodeMemberArrays(prefix: "wind_speed_10m_max_member")
    windDirection10mDominantMembers = container.decodeMemberArrays(
      prefix: "wind_direction_10m_dominant_member"
    )
  }
}

struct DailyEnsembleDayPoint: Identifiable {
  let id: Int
  let date: Date
  let temperatureMin: Double?
  let temperatureMax: Double?
  let temperatureMinMemberLow: Double?
  let temperatureMinMemberHigh: Double?
  let temperatureMaxMemberLow: Double?
  let temperatureMaxMemberHigh: Double?
  let precipitationSum: Double?
  let precipitationSumMemberLow: Double?
  let precipitationSumMemberHigh: Double?
  let windSpeedMin: Double?
  let windSpeedMax: Double?
  let windSpeedMinMemberLow: Double?
  let windSpeedMinMemberHigh: Double?
  let windSpeedMaxMemberLow: Double?
  let windSpeedMaxMemberHigh: Double?
  let windDirection: Double?
  let windDirectionMemberLow: Double?
  let windDirectionMemberHigh: Double?

  var hasChartData: Bool {
    [
      temperatureMin,
      temperatureMax,
      temperatureMinMemberLow,
      temperatureMinMemberHigh,
      temperatureMaxMemberLow,
      temperatureMaxMemberHigh,
      precipitationSum,
      precipitationSumMemberLow,
      precipitationSumMemberHigh,
      windSpeedMin,
      windSpeedMax,
      windSpeedMinMemberLow,
      windSpeedMinMemberHigh,
      windSpeedMaxMemberLow,
      windSpeedMaxMemberHigh,
    ].contains { $0 != nil }
  }
}

extension DailyEnsembleForecastResponse {
  var dayPoints: [DailyEnsembleDayPoint] {
    (0..<daily.time.count).compactMap { index in
      let dayString = daily.time[index]
      guard let date = Self.dayFormatter.date(from: dayString) else { return nil }
      let point = DailyEnsembleDayPoint(
        id: index,
        date: date,
        temperatureMin: daily.temperature2mMinMembers.mean(at: index),
        temperatureMax: daily.temperature2mMaxMembers.mean(at: index),
        temperatureMinMemberLow: daily.temperature2mMinMembers.extreme(at: index, using: <),
        temperatureMinMemberHigh: daily.temperature2mMinMembers.extreme(at: index, using: >),
        temperatureMaxMemberLow: daily.temperature2mMaxMembers.extreme(at: index, using: <),
        temperatureMaxMemberHigh: daily.temperature2mMaxMembers.extreme(at: index, using: >),
        precipitationSum: daily.precipitationSumMembers.mean(at: index),
        precipitationSumMemberLow: daily.precipitationSumMembers.extreme(at: index, using: <),
        precipitationSumMemberHigh: daily.precipitationSumMembers.extreme(at: index, using: >),
        windSpeedMin: daily.windSpeed10mMinMembers.mean(at: index),
        windSpeedMax: daily.windSpeed10mMaxMembers.mean(at: index),
        windSpeedMinMemberLow: daily.windSpeed10mMinMembers.extreme(at: index, using: <),
        windSpeedMinMemberHigh: daily.windSpeed10mMinMembers.extreme(at: index, using: >),
        windSpeedMaxMemberLow: daily.windSpeed10mMaxMembers.extreme(at: index, using: <),
        windSpeedMaxMemberHigh: daily.windSpeed10mMaxMembers.extreme(at: index, using: >),
        windDirection: daily.windDirection10mDominantMembers.mean(at: index),
        windDirectionMemberLow: daily.windDirection10mDominantMembers.extreme(at: index, using: <),
        windDirectionMemberHigh: daily.windDirection10mDominantMembers.extreme(at: index, using: >)
      )

      return point.hasChartData ? point : nil
    }
  }

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()
}

private struct DynamicCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
    self.intValue = nil
  }

  init?(intValue: Int) {
    self.stringValue = String(intValue)
    self.intValue = intValue
  }
}

private extension KeyedDecodingContainer where Key == DynamicCodingKey {
  func decodeStringArray(forKey key: String) throws -> [String] {
    guard let codingKey = DynamicCodingKey(stringValue: key) else { return [] }
    return try decode([String].self, forKey: codingKey)
  }

  func decodeOptionalDoubleArray(forKey key: String) -> [Double?] {
    guard let codingKey = DynamicCodingKey(stringValue: key) else { return [] }
    return (try? decodeIfPresent([Double?].self, forKey: codingKey)) ?? []
  }

  func decodeMemberArrays(prefix: String) -> [[Double?]] {
    allKeys
      .filter { $0.stringValue.hasPrefix(prefix) }
      .sorted { $0.stringValue < $1.stringValue }
      .compactMap { try? decodeIfPresent([Double?].self, forKey: $0) }
  }
}

private extension Array where Element == Double? {
  func value(at index: Int) -> Double? {
    guard indices.contains(index) else { return nil }
    return self[index]
  }
}

private extension Array where Element == [Double?] {
  func extreme(at index: Int, using areInIncreasingOrder: (Double, Double) -> Bool) -> Double? {
    compactMap { $0.value(at: index) }.min(by: areInIncreasingOrder)
  }

  func mean(at index: Int) -> Double? {
    let values = compactMap { $0.value(at: index) }
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
  }
}
