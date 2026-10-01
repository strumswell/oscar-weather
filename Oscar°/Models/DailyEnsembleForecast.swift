import Foundation

/// The Open-Meteo ensemble response. Every variable arrives once per run under
/// dynamic keys (`temperature_2m_max`, `temperature_2m_max_member01`, …).
struct DailyEnsembleForecastResponse: Decodable {
  let utcOffsetSeconds: Int
  let timezone: String?
  let dailyUnits: [String: String]
  let daily: DailyEnsembleForecastDaily

  enum CodingKeys: String, CodingKey {
    case utcOffsetSeconds = "utc_offset_seconds"
    case timezone
    case dailyUnits = "daily_units"
    case daily
  }

  var timeZone: TimeZone {
    timezone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .current
  }
}

/// Per variable, one series per run: the control run first, then the members.
struct DailyEnsembleForecastDaily: Decodable {
  let time: [String]
  let highs: [[Double?]]
  let lows: [[Double?]]
  let precipitation: [[Double?]]
  let snowfall: [[Double?]]
  let wind: [[Double?]]
  let weatherCodes: [[Double?]]
  let cloudCover: [[Double?]]

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    time = try container.decode([String].self, forKey: DynamicCodingKey(stringValue: "time"))
    highs = container.runs(of: "temperature_2m_max")
    lows = container.runs(of: "temperature_2m_min")
    precipitation = container.runs(of: "precipitation_sum")
    snowfall = container.runs(of: "snowfall_sum")
    wind = container.runs(of: "wind_speed_10m_max")
    weatherCodes = container.runs(of: "weather_code")
    cloudCover = container.runs(of: "cloud_cover_mean")
  }
}

/// One day across all runs of an ensemble.
struct EnsembleDay: Identifiable {
  let id: Int
  let noon: Double
  let runs: Int
  let high: EnsembleSpread?
  let low: EnsembleSpread?
  let precipitation: EnsembleSpread?
  let wind: EnsembleSpread?
  let snowfall: Double?
  let cloudCover: Double?
  let sky: EnsembleSkyMix
}

/// Where a day's runs land: the extremes, the middle eight in ten, the median.
struct EnsembleSpread {
  let lowest: Double
  let low: Double
  let median: Double
  let high: Double
  let highest: Double

  init?(_ values: [Double]) {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    func quantile(_ q: Double) -> Double {
      let position = q * Double(sorted.count - 1)
      let lower = Int(position)
      let upper = min(lower + 1, sorted.count - 1)
      return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }
    self.init(lowest: sorted[0], low: quantile(0.1), median: quantile(0.5), high: quantile(0.9), highest: sorted[sorted.count - 1])
  }

  private init(lowest: Double, low: Double, median: Double, high: Double, highest: Double) {
    self.lowest = lowest
    self.low = low
    self.median = median
    self.high = high
    self.highest = highest
  }

  func map(_ transform: (Double) -> Double) -> EnsembleSpread {
    EnsembleSpread(
      lowest: transform(lowest), low: transform(low), median: transform(median),
      high: transform(high), highest: transform(highest)
    )
  }
}

/// The weather a day's runs settle on, coarsened to what a sky can show.
enum EnsembleSky: CaseIterable {
  case sun, clouds, rain, snow

  init(weatherCode code: Int) {
    switch code {
    case 0...2: self = .sun
    case 71...77, 85, 86: self = .snow
    case 51...67, 80...82, 95...99: self = .rain
    default: self = .clouds
    }
  }
}

struct EnsembleSkyMix {
  let counts: [EnsembleSky: Int]
  let total: Int
  let dominant: EnsembleSky?
  /// The most common weather code among the dominant runs; what the sim renders.
  let dominantCode: Int?

  init(codes: [Int]) {
    let counts = Dictionary(grouping: codes, by: EnsembleSky.init(weatherCode:)).mapValues(\.count)
    let dominant = EnsembleSky.allCases
      .filter { counts[$0] != nil }
      .max { counts[$0, default: 0] < counts[$1, default: 0] }
    let codeCounts = Dictionary(grouping: codes.filter { EnsembleSky(weatherCode: $0) == dominant }, by: { $0 })
      .mapValues(\.count)
    self.counts = counts
    self.total = codes.count
    self.dominant = dominant
    self.dominantCode = codeCounts.keys.sorted().max { codeCounts[$0, default: 0] < codeCounts[$1, default: 0] }
  }

  func share(of sky: EnsembleSky) -> Double {
    total > 0 ? Double(counts[sky, default: 0]) / Double(total) : 0
  }
}

extension DailyEnsembleForecastResponse {
  var days: [EnsembleDay] {
    daily.time.indices.compactMap { index in
      guard let midnight = Self.dayFormatter.date(from: daily.time[index]) else { return nil }
      let highs = daily.highs.values(at: index)
      guard !highs.isEmpty else { return nil }
      let codes = daily.weatherCodes.values(at: index).map { Int($0) }
      return EnsembleDay(
        id: index,
        noon: midnight.timeIntervalSince1970 + 43_200 - Double(utcOffsetSeconds),
        runs: highs.count,
        high: EnsembleSpread(highs),
        low: EnsembleSpread(daily.lows.values(at: index)),
        precipitation: EnsembleSpread(daily.precipitation.values(at: index).map { max(0, $0) }),
        wind: EnsembleSpread(daily.wind.values(at: index)),
        snowfall: EnsembleSpread(daily.snowfall.values(at: index))?.median,
        cloudCover: EnsembleSpread(daily.cloudCover.values(at: index))?.median,
        sky: EnsembleSkyMix(codes: codes)
      )
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
  let intValue: Int? = nil

  init(stringValue: String) {
    self.stringValue = stringValue
  }

  init?(intValue: Int) {
    return nil
  }
}

private extension KeyedDecodingContainer where Key == DynamicCodingKey {
  /// The control run (`name`) sorts ahead of its members (`name_member01…`).
  func runs(of name: String) -> [[Double?]] {
    allKeys
      .filter { $0.stringValue == name || $0.stringValue.hasPrefix(name + "_member") }
      .sorted { $0.stringValue < $1.stringValue }
      .compactMap { try? decodeIfPresent([Double?].self, forKey: $0) }
  }
}

private extension Array where Element == [Double?] {
  func values(at index: Int) -> [Double] {
    compactMap { $0.indices.contains(index) ? $0[index] : nil }
  }
}
