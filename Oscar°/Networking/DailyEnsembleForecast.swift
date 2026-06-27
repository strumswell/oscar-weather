import CoreLocation
import CryptoKit
import Foundation
import OSLog

enum DailyEnsembleModel: String, CaseIterable, Identifiable {
  case ecmwfAIFS025Ensemble = "ecmwf_aifs025_ensemble"
  case ecmwfIFS025Ensemble = "ecmwf_ifs025_ensemble"
  case googleWeatherNext2Ensemble = "google_weathernext2_ensemble"
  case ncepAIGFS025 = "ncep_aigefs025"
  case ncepGEFS05 = "ncep_gefs05"
  case iconGlobalEPS = "icon_global_eps"
  case iconEUEPS = "icon_eu_eps"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .ecmwfAIFS025Ensemble:
      return "AIFS"
    case .ecmwfIFS025Ensemble:
      return "IFS ENS"
    case .googleWeatherNext2Ensemble:
      return "WeatherNext2"
    case .ncepAIGFS025:
      return "AI GEFS"
    case .ncepGEFS05:
      return "GEFS"
    case .iconGlobalEPS:
      return "ICON Global"
    case .iconEUEPS:
      return "ICON EU"
    }
  }

  var providerName: String {
    switch self {
    case .ecmwfAIFS025Ensemble, .ecmwfIFS025Ensemble:
      return "ECMWF"
    case .googleWeatherNext2Ensemble:
      return "Google"
    case .ncepAIGFS025, .ncepGEFS05:
      return "NOAA"
    case .iconGlobalEPS, .iconEUEPS:
      return "Deutscher Wetterdienst (DWD)"
    }
  }

  var technicalName: String {
    switch self {
    case .ecmwfAIFS025Ensemble:
      return "AIFS 0.25°"
    case .ecmwfIFS025Ensemble:
      return "IFS ENS 0.25°"
    case .googleWeatherNext2Ensemble:
      return "WeatherNext 2"
    case .ncepAIGFS025:
      return "AIGFS 0.25°"
    case .ncepGEFS05:
      return "GFS Ensemble 0.5°"
    case .iconGlobalEPS:
      return "ICON-EPS"
    case .iconEUEPS:
      return "ICON-EU-EPS"
    }
  }

  var region: String {
    switch self {
    case .iconEUEPS:
      return "Europa"
    default:
      return "Global"
    }
  }

  var resolution: String {
    switch self {
    case .ecmwfAIFS025Ensemble, .ecmwfIFS025Ensemble, .ncepAIGFS025, .googleWeatherNext2Ensemble:
      return "25 km, 6-stündlich"
    case .ncepGEFS05:
      return "50 km, 3-stündlich"
    case .iconGlobalEPS:
      return "26 km, stündlich"
    case .iconEUEPS:
      return "13 km, stündlich"
    }
  }

  var members: Int {
    switch self {
    case .ecmwfAIFS025Ensemble, .ecmwfIFS025Ensemble:
      return 51
    case .googleWeatherNext2Ensemble:
      return 35
    case .ncepAIGFS025, .ncepGEFS05:
      return 31
    case .iconGlobalEPS, .iconEUEPS:
      return 40
    }
  }

  var forecastLength: String {
    switch self {
    case .ecmwfAIFS025Ensemble, .ecmwfIFS025Ensemble, .googleWeatherNext2Ensemble:
      return "15 Tage"
    case .ncepAIGFS025:
      return "16 Tage"
    case .ncepGEFS05:
      return "35 Tage"
    case .iconGlobalEPS:
      return "7,5 Tage"
    case .iconEUEPS:
      return "5 Tage"
    }
  }

  var updateFrequency: String {
    switch self {
    case .ecmwfAIFS025Ensemble, .ncepAIGFS025, .ncepGEFS05, .iconEUEPS:
      return "alle 6 Stunden"
    case .ecmwfIFS025Ensemble, .googleWeatherNext2Ensemble, .iconGlobalEPS:
      return "alle 12 Stunden"
    }
  }

  var menuSubtitle: String {
    switch self {
    case .ecmwfAIFS025Ensemble: return "25 km · 15 Tage"
    case .ecmwfIFS025Ensemble: return "25 km · 15 Tage"
    case .googleWeatherNext2Ensemble: return "25 km · 15 Tage"
    case .ncepAIGFS025: return "25 km · 16 Tage"
    case .ncepGEFS05: return "50 km · 35 Tage"
    case .iconGlobalEPS: return "26 km · 7,5 Tage"
    case .iconEUEPS: return "13 km · 5 Tage"
    }
  }

  enum Provider: String, CaseIterable {
    case ecmwf = "ECMWF"
    case google = "Google"
    case noaa = "NOAA"
    case dwd = "DWD"
  }

  var provider: Provider {
    switch self {
    case .ecmwfAIFS025Ensemble, .ecmwfIFS025Ensemble: return .ecmwf
    case .googleWeatherNext2Ensemble: return .google
    case .ncepAIGFS025, .ncepGEFS05: return .noaa
    case .iconGlobalEPS, .iconEUEPS: return .dwd
    }
  }

  static var modelsByProvider: [(provider: Provider, models: [DailyEnsembleModel])] {
    Provider.allCases.map { provider in
      (provider, DailyEnsembleModel.allCases.filter { $0.provider == provider })
    }
  }

  var shortAssessment: String {
    switch self {
    case .ecmwfAIFS025Ensemble:
      return "Mit 51 Mitgliedern und globaler 25-km-Abdeckung eignet sich AIFS gut, um mittelfristige Unsicherheit bis etwa 15 Tage einzuordnen. Da das Modell 6-stündlich und nicht hochaufgelöst ist, können lokale Details bei Wind und Temperatur geglättet wirken."
    case .ecmwfIFS025Ensemble:
      return "Das klassische ECMWF-Ensemble (EPS) mit 51 Mitgliedern bei 0,25°-Auflösung. Gilt weithin als Referenz für mittelfristige Vorhersagen bis 15 Tage – besonders zuverlässig für synoptische Ereignisse auf globaler Skala."
    case .googleWeatherNext2Ensemble:
      return "Googles KI-basiertes Ensemble mit globaler Abdeckung und bis zu 15 Tagen Reichweite. Mit 35 Mitgliedern bei 25-km-Gitter eignet es sich gut, um mittelfristige Unsicherheit einzuordnen."
    case .ncepAIGFS025:
      return "Die globale 25-km-Abdeckung und bis zu 16 Tage Reichweite sind ein guter Kompromiss für die nächsten ein bis zwei Wochen. Die 6-stündliche Auflösung macht genaue Timing-Details allerdings gröber als bei 3-stündlichen Ensembles."
    case .ncepGEFS05:
      return "GEFS 0.5° ist hier die Langfrist-Option mit bis zu 35 Tagen Reichweite. Wegen des groben 50-km-Gitters eignet es sich eher für großräumige Trends als für lokale Details."
    case .iconGlobalEPS:
      return "ICON Global EPS liefert ein globales Ensemble mit 40 Mitgliedern und stündlichen Daten, sinnvoll für kurze bis mittlere Trends weltweit. Die Vorhersage reicht dafür nur etwa 7,5 Tage."
    case .iconEUEPS:
      return "Für Europa ist ICON EU EPS die passendste Auswahl, mit feinerem 13-km-Gitter und 40 Mitgliedern. Die Vorhersage reicht nur etwa 5 Tage und ist nicht für globale Orte gedacht."
    }
  }
}

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

actor DailyEnsembleForecastCache {
  static let shared = DailyEnsembleForecastCache()

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Oscar",
    category: "Ensemble"
  )

  private struct Metadata: Codable {
    let key: String
    let timestamp: Date
  }

  private let lifetime: TimeInterval = 43_200
  private let fileManager = FileManager.default
  private let cacheDirectory: URL
  private var memoryCache: [String: (Date, Data)] = [:]

  private init() {
    let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    cacheDirectory = cachesDirectory.appendingPathComponent("DailyEnsembleAPICache", isDirectory: true)
  }

  func data(for key: String) -> Data? {
    let now = Date()

    if let (timestamp, data) = memoryCache[key], now.timeIntervalSince(timestamp) < lifetime {
      return data
    }

    let stem = fileStem(for: key)
    let metadataURL = cacheDirectory.appendingPathComponent("\(stem).json")
    let bodyURL = cacheDirectory.appendingPathComponent("\(stem).body")

    guard
      let metadataData = try? Data(contentsOf: metadataURL),
      let metadata = try? JSONDecoder().decode(Metadata.self, from: metadataData),
      now.timeIntervalSince(metadata.timestamp) < lifetime,
      let data = try? Data(contentsOf: bodyURL)
    else {
      try? fileManager.removeItem(at: metadataURL)
      try? fileManager.removeItem(at: bodyURL)
      memoryCache.removeValue(forKey: key)
      return nil
    }

    memoryCache[key] = (metadata.timestamp, data)
    return data
  }

  func set(_ data: Data, for key: String) {
    let timestamp = Date()
    memoryCache[key] = (timestamp, data)

    try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

    let stem = fileStem(for: key)
    let metadataURL = cacheDirectory.appendingPathComponent("\(stem).json")
    let bodyURL = cacheDirectory.appendingPathComponent("\(stem).body")
    let metadata = Metadata(key: key, timestamp: timestamp)

    do {
      try data.write(to: bodyURL, options: .atomic)
      try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
    } catch {
      Self.logger.error("Failed to write ensemble cache entry: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func fileStem(for key: String) -> String {
    SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
  }
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
