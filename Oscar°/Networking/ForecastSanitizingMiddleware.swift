import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Open-Meteo returns `null` for variables a selected model doesn't provide and for time steps
/// beyond a model's forecast horizon. Most series are decoded as non-optional `[Double]`, so a
/// single `null` makes the entire forecast fail to decode (the user then sees stale or empty data).
///
/// This middleware cleans `getForecast` responses before decoding: series that are missing from
/// the start are dropped, every block is truncated to the range free of `null`s (so a short-range
/// model shows only the days it covers), and required `current` scalars that came back `null` are
/// filled with a neutral default. For `best_match` — which never returns `null` — it is a no-op.
final class ForecastSanitizingMiddleware: ClientMiddleware {
  /// Series the schema already declares nullable; their generated type tolerates `null`.
  private static let nullableHourly: Set<String> = [
    "precipitation_probability",
    "soil_temperature_0cm", "soil_temperature_6cm", "soil_temperature_18cm", "soil_temperature_54cm",
    "soil_moisture_0_1cm", "soil_moisture_1_3cm", "soil_moisture_3_9cm",
    "soil_moisture_9_27cm", "soil_moisture_27_81cm",
  ]
  private static let nullableDaily: Set<String> = ["precipitation_probability_max"]
  private static let requiredCurrent: Set<String> = [
    "cloudcover", "time", "temperature", "windspeed", "wind_direction_10m", "weathercode",
  ]

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    let (response, responseBody) = try await next(request, body, baseURL)

    guard operationID == "getForecast",
      (200...299).contains(response.status.code),
      let responseBody
    else {
      return (response, responseBody)
    }

    let data = try await Data(collecting: responseBody, upTo: 10 * 1024 * 1024)
    guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      return (response, HTTPBody(data))
    }

    sanitizeSeries(&root, key: "hourly", nullableFields: Self.nullableHourly)
    sanitizeSeries(&root, key: "daily", nullableFields: Self.nullableDaily)
    sanitizeCurrent(&root)
    sanitizeUnits(&root, request: request)

    guard let cleaned = try? JSONSerialization.data(withJSONObject: root) else {
      return (response, HTTPBody(data))
    }
    return (response, HTTPBody(cleaned))
  }

  /// Cleans a block of parallel arrays (`hourly`/`daily`) keyed off its `time` spine.
  private func sanitizeSeries(_ root: inout [String: Any], key: String, nullableFields: Set<String>) {
    guard var block = root[key] as? [String: Any],
      let time = block["time"] as? [Any]
    else { return }

    var validLength = time.count

    for field in Array(block.keys) where field != "time" {
      guard let array = block[field] as? [Any] else { continue }
      if nullableFields.contains(field) {
        validLength = min(validLength, array.count)
        continue
      }
      // Non-nullable series: drop it if it never starts, otherwise cut at its first null.
      if array.isEmpty || (array.first as? NSNull) != nil {
        block.removeValue(forKey: field)
        continue
      }
      let firstNull = array.firstIndex { $0 is NSNull } ?? array.count
      validLength = min(validLength, firstNull)
    }

    validLength = max(0, validLength)
    for field in Array(block.keys) {
      guard let array = block[field] as? [Any], array.count > validLength else { continue }
      block[field] = Array(array.prefix(validLength))
    }

    root[key] = block
  }

  /// Maps a `current` scalar to the matching `hourly` series it can be backfilled from.
  private static let currentToHourly: [String: String] = [
    "time": "time",
    "temperature": "temperature_2m",
    "cloudcover": "cloudcover",
    "windspeed": "windspeed_10m",
    "wind_direction_10m": "winddirection_10m",
    "weathercode": "weathercode",
    "precipitation": "precipitation",
    "is_day": "is_day",
  ]

  /// `current` is a single object whose required scalars must stay present and non-null. A missing
  /// or `null` value is backfilled from the matching `hourly` series at the current time, falling
  /// back to `0` only if the model provides no hourly value either.
  private func sanitizeCurrent(_ root: inout [String: Any]) {
    guard var current = root["current"] as? [String: Any] else { return }

    let hourly = root["hourly"] as? [String: Any]
    let hourlyTime = hourly?["time"] as? [Any]
    let currentTime = (current["time"] as? NSNumber)?.doubleValue
    let index = hourlyIndex(for: currentTime, in: hourlyTime)

    var fieldsToFill = Set(current.keys.filter { (current[$0] as? NSNull) != nil })
    for required in Self.requiredCurrent where current[required] == nil {
      fieldsToFill.insert(required)
    }

    for field in fieldsToFill {
      if let value = hourlyValue(for: field, at: index, hourly: hourly) {
        current[field] = value
      } else if Self.requiredCurrent.contains(field) {
        current[field] = 0
      } else {
        current.removeValue(forKey: field)
      }
    }
    root["current"] = current
  }

  /// Some models report a unit of `"undefined"`; the app would then display that literal string
  /// (e.g. "7.6 undefined" for wind). The values are in the units requested via the `*_unit` query
  /// params, so resolve those — falling back to known fixed units (°, %, hPa, …) per variable.
  private func sanitizeUnits(_ root: inout [String: Any], request: HTTPRequest) {
    let query = queryParameters(from: request)
    let speedUnit = Self.speedUnit(query["windspeed_unit"] ?? query["wind_speed_unit"])
    let tempUnit = Self.temperatureUnit(query["temperature_unit"])
    let precipUnit = Self.precipitationUnit(query["precipitation_unit"])

    for key in ["hourly_units", "daily_units", "current_units"] {
      guard var units = root[key] as? [String: Any] else { continue }
      for field in Array(units.keys) where (units[field] as? String) == "undefined" {
        units[field] = Self.resolvedUnit(
          for: field, speed: speedUnit, temperature: tempUnit, precipitation: precipUnit)
      }
      root[key] = units
    }
  }

  private func queryParameters(from request: HTTPRequest) -> [String: String] {
    guard let path = request.path, let components = URLComponents(string: path) else { return [:] }
    var parameters: [String: String] = [:]
    for item in components.queryItems ?? [] {
      if let value = item.value { parameters[item.name] = value }
    }
    return parameters
  }

  private static func speedUnit(_ raw: String?) -> String {
    switch raw {
    case "ms": return "m/s"
    case "mph": return "mph"
    case "kn": return "kn"
    default: return "km/h"
    }
  }

  private static func temperatureUnit(_ raw: String?) -> String {
    raw == "fahrenheit" ? "°F" : "°C"
  }

  private static func precipitationUnit(_ raw: String?) -> String {
    raw == "inch" ? "inch" : "mm"
  }

  private static func resolvedUnit(
    for field: String, speed: String, temperature: String, precipitation: String
  ) -> String {
    let name = field.lowercased()
    if name.contains("winddirection") || name.contains("wind_direction") { return "°" }
    if name.contains("windspeed") || name.contains("wind_speed")
      || name.contains("windgust") || name.contains("wind_gust") { return speed }
    if name.contains("soil_moisture") { return "m³/m³" }
    if name.contains("temperature") || name.contains("dewpoint") || name.contains("dew_point") {
      return temperature
    }
    if name.contains("humidity") || name.contains("cloudcover") || name.contains("cloud_cover") {
      return "%"
    }
    if name.contains("pressure") { return "hPa" }
    if name.contains("snowfall") || name.contains("snow_depth") || name.contains("snow_height") {
      return "cm"
    }
    if name.contains("precipitation") || name.contains("rain") || name.contains("showers") {
      return precipitation
    }
    return ""
  }

  /// Index of the hourly step at or just before `time` (the current step), or `0` / `nil`.
  private func hourlyIndex(for time: Double?, in hourlyTime: [Any]?) -> Int? {
    guard let hourlyTime, !hourlyTime.isEmpty else { return nil }
    guard let time else { return 0 }
    var index = 0
    for (i, value) in hourlyTime.enumerated() {
      guard let stamp = (value as? NSNumber)?.doubleValue, stamp <= time else { break }
      index = i
    }
    return index
  }

  private func hourlyValue(for currentField: String, at index: Int?, hourly: [String: Any]?) -> Any? {
    guard let index,
      let hourlyField = Self.currentToHourly[currentField],
      let array = hourly?[hourlyField] as? [Any],
      array.indices.contains(index)
    else { return nil }
    let value = array[index]
    return value is NSNull ? nil : value
  }
}
