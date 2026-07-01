//
//  APIClient.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.01.24.
//

import CoreLocation
import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// Base URL of the companion oscar-server backend (radar, models, precip series,
/// notifications). Defined here because `APIClient` is a member of every target
/// (incl. the watch widget extension), unlike the MapKit-dependent radar files.
let radarBaseURL = "https://server.oscars.love"

enum AlertResponse {
  case brightsky(Operations.getAlerts.Output.Ok.Body.jsonPayload)
  case canadian(Operations.getCanadianWeatherAlerts.Output.Ok.Body.jsonPayload)
}

// TODO: Caching for API results
final class APIClient: Sendable {
  static let shared = APIClient()

  let openMeteo: Client
  let openMeteoAqi: Client
  let openMeteoGeo: Client
  let openMeteoEnsemble: Client
  let openMeteoArchive: Client
  let brightsky: Client
  let canadaWeather: Client
  let rainViewer: Client

  init() {
    openMeteo = APIClient.get(
      url: Self.serverURL(Servers.server1),
      prepending: [ForecastSanitizingMiddleware()]
    )
    openMeteoAqi = APIClient.get(url: Self.serverURL(Servers.server2))
    openMeteoGeo = APIClient.get(url: Self.serverURL(Servers.server3))
    openMeteoEnsemble = APIClient.get(url: Self.ensembleServerURL)
    openMeteoArchive = APIClient.get(url: Self.archiveServerURL)
    brightsky = APIClient.get(url: Self.serverURL(Servers.server4))
    canadaWeather = APIClient.get(url: Self.serverURL(Servers.server5))
    rainViewer = APIClient.get(url: Self.serverURL(Servers.server6))
  }

  private static let ensembleServerURL = URL(string: "https://ensemble-api.open-meteo.com")!
  private static let archiveServerURL = URL(string: "https://archive-api.open-meteo.com")!

  /// The generated `Servers.serverN()` build compile-time-constant base URLs; a failure is a
  /// spec/build error, so fail loudly with a clear message instead of force-trying.
  private static func serverURL(_ make: () throws -> URL) -> URL {
    do {
      return try make()
    } catch {
      fatalError("Failed to construct OpenAPI server URL: \(error.localizedDescription)")
    }
  }

  class func get(url: URL, prepending middlewares: [any ClientMiddleware] = []) -> Client {
    return Client(
      serverURL: url,
      transport: URLSessionTransport(),
      middlewares: middlewares + [
        CachingMiddleware(cacheTime: 60),
        ContactIdentityMiddleware(),
        RetryingMiddleware(
          signals: [.code(429), .range(500..<600), .errorThrown],
          policy: .upToAttempts(count: 3),
          delay: .exponentialWithJitter(base: 0.5, maxSeconds: 8)
        ),
      ]
    )
  }

  func getForecast(
    coordinates: CLLocationCoordinate2D,
    forecastDays: Operations.getForecast.Input.Query.forecast_daysPayload? = ._14,
    hourly: [Operations.getForecast.Input.Query.hourlyPayloadPayload]? = nil
  ) async throws -> Operations.getForecast.Output.Ok.Body.jsonPayload {
    let outboundCoordinates = LocationService.outboundCoordinate(coordinates)

    // Read units from shared app-group defaults rather than the viewContext-bound managed object:
    // the widget process caches its Core Data `settings` at launch and would otherwise keep
    // requesting a stale unit (e.g. still Fahrenheit after the app switched to Celsius).
    let temperatureUnit = SettingService.resolvedTemperatureUnit
    let precipitationUnit = SettingService.resolvedPrecipitationUnit
    let windSpeedUnit = WindSpeedUnit(settingValue: SettingService.resolvedWindSpeedUnit)
    let hourlyFields = hourly ?? [
      .temperature_2m, .apparent_temperature, .precipitation, .snowfall, .weathercode,
      .cloudcover,
      .windspeed_10m, .windspeed_80m, .windspeed_120m, .windspeed_180m, .winddirection_10m,
      .precipitation_probability, .is_day, .relativehumidity_2m, .pressure_msl,
      .soil_temperature_0cm, .soil_temperature_6cm, .soil_temperature_18cm,
      .soil_temperature_54cm, .soil_moisture_0_1cm, .soil_moisture_1_3cm, .soil_moisture_3_9cm,
      .soil_moisture_9_27cm, .soil_moisture_27_81cm, .et0_fao_evapotranspiration,
    ]

    var query: Operations.getForecast.Input.Query = .init(
      latitude: outboundCoordinates.latitude,
      longitude: outboundCoordinates.longitude,
      hourly: hourlyFields,
      daily: [
        .precipitation_probability_max, .precipitation_sum, .sunrise, .sunset, .temperature_2m_max,
        .temperature_2m_min, .weathercode,
      ],
      current: [
        .cloudcover, .temperature, .wind_direction_10m, .weathercode, .windspeed, .precipitation,
        .is_day,
      ],
      temperature_unit: Operations.getForecast.Input.Query.temperature_unitPayload(
        rawValue: temperatureUnit),
      windspeed_unit: Operations.getForecast.Input.Query.windspeed_unitPayload(
        rawValue: windSpeedUnit.apiRawValue),
      precipitation_unit: Operations.getForecast.Input.Query.precipitation_unitPayload(
        rawValue: precipitationUnit),
      timeformat: .unixtime,
      timezone: "auto",
      forecast_days: forecastDays
    )

    let modelPreference = SettingService.resolvedForecastModelPreference

    // A user-forced model overrides the automatic best_match and regional logic below.
    if modelPreference != .bestMatch {
      query.models = Operations.getForecast.Input.Query.modelsPayload(rawValue: modelPreference.apiValue)
    }
    // For regions where ICON model is better
    else if coordinates.country() == .spain || coordinates.country() == .portugal  //|| coordinates.country() == .centralEurope
    {
      // First request: Get 7 days with ICON model
      query.models = .icon_seamless
      query.forecast_days = ._7

      let iconResponse = try await openMeteo.getForecast(.init(query: query))
      var iconForecast: Operations.getForecast.Output.Ok.Body.jsonPayload

      switch iconResponse {
      case let .ok(response):
        switch response.body {
        case .json(let result):
          iconForecast = result
        }
      case .badRequest(_), .undocumented(statusCode: _, _):
        // No usable data for this location/model — surface the failure so refresh()
        // keeps the last-known-good forecast instead of showing a fabricated one.
        throw URLError(.badServerResponse)
      }

      // Second request: Get 14 days with best_match model
      query.models = .best_match
      query.forecast_days = ._14

      let bestMatchResponse = try await openMeteo.getForecast(.init(query: query))

      switch bestMatchResponse {
      case let .ok(response):
        switch response.body {
        case .json(let result):
          // Merge the daily forecasts: first 7 days from ICON, next 7 days from best_match
          guard var iconDaily = iconForecast.daily,
            let bestMatchDaily = result.daily,
            bestMatchDaily.time.count > 7,
            let maxTemps = bestMatchDaily.temperature_2m_max,
            let minTemps = bestMatchDaily.temperature_2m_min,
            let precip = bestMatchDaily.precipitation_sum,
            let precipProb = bestMatchDaily.precipitation_probability_max,
            let codes = bestMatchDaily.weathercode,
            let sunrises = bestMatchDaily.sunrise,
            let sunsets = bestMatchDaily.sunset
          else {
            return iconForecast
          }

          // Append best_match days beyond what ICON actually returned, keyed off ICON's own
          // day count rather than a hardcoded 7 (the sanitizer may trim ICON to fewer days),
          // so the merged timeline stays contiguous and the parallel arrays stay aligned.
          let startIndex = iconDaily.time.count
          guard bestMatchDaily.time.count > startIndex else { return iconForecast }
          iconDaily.time.append(contentsOf: bestMatchDaily.time.suffix(from: startIndex))
          iconDaily.temperature_2m_max?.append(contentsOf: maxTemps.suffix(from: startIndex))
          iconDaily.temperature_2m_min?.append(contentsOf: minTemps.suffix(from: startIndex))
          iconDaily.precipitation_sum?.append(contentsOf: precip.suffix(from: startIndex))
          iconDaily.precipitation_probability_max?.append(
            contentsOf: precipProb.suffix(from: startIndex))
          iconDaily.weathercode?.append(contentsOf: codes.suffix(from: startIndex))
          iconDaily.sunrise?.append(contentsOf: sunrises.suffix(from: startIndex))
          iconDaily.sunset?.append(contentsOf: sunsets.suffix(from: startIndex))

          iconForecast.daily = iconDaily
          return iconForecast
        }
      case .badRequest(_), .undocumented(statusCode: _, _):
        return iconForecast  // Return just the ICON forecast if best_match fails
      }
    }

    // For all other regions, proceed with normal request
    let response = try await openMeteo.getForecast(.init(query: query))

    switch response {
    case let .ok(response):
      switch response.body {
      case .json(let result):
        return result
      }
    case .badRequest(_), .undocumented(statusCode: _, _):
      // A user-forced model may have no data for this location ("No data is available for this
      // location"). Fall back to best_match first; if that also fails, surface the error so
      // refresh() keeps the last-known-good forecast rather than showing a fabricated one.
      if modelPreference != .bestMatch,
        let fallback = try await fallbackToBestMatch(query: query, failedModel: modelPreference)
      {
        return fallback
      }
      throw URLError(.badServerResponse)
    }
  }

  /// Re-requests the forecast with `best_match` after a forced model returned no data, and posts a
  /// notification so the app can inform the user. Returns `nil` if `best_match` also fails.
  private func fallbackToBestMatch(
    query: Operations.getForecast.Input.Query,
    failedModel: ForecastModelPreference
  ) async throws -> Operations.getForecast.Output.Ok.Body.jsonPayload? {
    var query = query
    query.models = .best_match

    let response = try await openMeteo.getForecast(.init(query: query))
    switch response {
    case let .ok(response):
      switch response.body {
      case .json(let result):
        notifyModelFallback(failedModel)
        return result
      }
    case .badRequest(_), .undocumented(statusCode: _, _):
      return nil
    }
  }

  private func notifyModelFallback(_ model: ForecastModelPreference) {
    let modelName = model.name
    DispatchQueue.main.async {
      NotificationCenter.default.post(
        name: .forecastModelFallback,
        object: nil,
        userInfo: ["modelName": modelName]
      )
    }
  }

  func getAirQuality(coordinates: CLLocationCoordinate2D) async throws
    -> Operations.getAirQuality.Output.Ok.Body.jsonPayload
  {
    let outboundCoordinates = LocationService.outboundCoordinate(coordinates)
    let fallbackForecast: Operations.getAirQuality.Output.Ok.Body.jsonPayload = .init(
      latitude: 0, longitude: 0)

    let response = try await openMeteoAqi.getAirQuality(
      .init(
        query: .init(
          latitude: outboundCoordinates.latitude,
          longitude: outboundCoordinates.longitude,
          timezone: "auto", timeformat: .unixtime, forecast_days: ._3,
          hourly: [
            .european_aqi, .european_aqi_no2, .european_aqi_o3, .european_aqi_pm10,
            .european_aqi_pm2_5, .european_aqi_so2, .uv_index, .alder_pollen, .birch_pollen,
            .grass_pollen, .mugwort_pollen, .ragweed_pollen
          ]
        )
      ))

    switch response {
    case let .ok(response):
      switch response.body {
      case .json(let result):
        return result
      }
    case .undocumented(statusCode: _, _):
      return fallbackForecast
    }
  }

  func getDailyEnsembleForecast(
    coordinates: CLLocationCoordinate2D,
    model: DailyEnsembleModel = .ecmwfAIFS025Ensemble
  ) async throws -> DailyEnsembleForecastResponse {
    let outboundCoordinates = LocationService.outboundCoordinate(coordinates)
    let windSpeedUnit = WindSpeedUnit(settingValue: SettingService.resolvedWindSpeedUnit)
    var components = URLComponents(string: "https://ensemble-api.open-meteo.com/v1/ensemble")!
    components.queryItems = [
      URLQueryItem(name: "latitude", value: String(outboundCoordinates.latitude)),
      URLQueryItem(name: "longitude", value: String(outboundCoordinates.longitude)),
      URLQueryItem(
        name: "daily",
        value: [
          "temperature_2m_min",
          "temperature_2m_max",
          "precipitation_sum",
          "wind_speed_10m_min",
          "wind_speed_10m_max",
          "wind_direction_10m_dominant",
        ].joined(separator: ",")
      ),
      URLQueryItem(name: "models", value: model.rawValue),
      URLQueryItem(
        name: "wind_speed_unit",
        value: windSpeedUnit.apiRawValue
      ),
      URLQueryItem(name: "timezone", value: "auto"),
      URLQueryItem(name: "forecast_days", value: "35"),
    ]

    guard let url = components.url else {
      throw URLError(.badURL)
    }

    let cacheKey = url.absoluteString
    let decoder = JSONDecoder()
    if let cachedData = await DailyEnsembleForecastCache.shared.data(for: cacheKey) {
      return try decoder.decode(DailyEnsembleForecastResponse.self, from: cachedData)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue(APIContactIdentity.userAgent, forHTTPHeaderField: "User-Agent")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else {
      throw URLError(.badServerResponse)
    }

    // Decode first so a malformed 200 body (schema drift, HTML error page) never poisons
    // the cache for its 12h lifetime and re-throws on every subsequent call.
    let decoded = try decoder.decode(DailyEnsembleForecastResponse.self, from: data)
    await DailyEnsembleForecastCache.shared.set(data, for: cacheKey)
    return decoded
  }

  /// Historical daily maximum temperatures (ERA5 reanalysis) for a coordinate over a date range.
  /// Backs the climate timeline. Coordinates are passed through unrounded because callers feed in
  /// the already grid-snapped `forecast.latitude/longitude`, which keeps the cache key stable.
  /// The (cold) full-history request is extremely heavy, so callers cache the result indefinitely
  /// and only ever fetch the missing recent days; this method itself stays a thin transport.
  func getArchive(
    latitude: Double,
    longitude: Double,
    startDate: String,
    endDate: String
  ) async throws -> Components.Schemas.ArchiveResponse {
    let response = try await openMeteoArchive.getArchive(
      .init(
        query: .init(
          latitude: latitude,
          longitude: longitude,
          start_date: startDate,
          end_date: endDate,
          daily: [.temperature_2m_max],
          models: .era5,
          timezone: "auto"
        )
      ))

    switch response {
    case let .ok(response):
      switch response.body {
      case .json(let result):
        return result
      }
    case .badRequest, .undocumented:
      throw URLError(.badServerResponse)
    }
  }

  func getAlerts(
    coordinates: CLLocationCoordinate2D,
    countryCode: String? = nil
  ) async throws -> AlertResponse {
    let useCanadian: Bool
    if let countryCode {
      useCanadian = countryCode == "CA"
    } else {
      useCanadian = isCanadianLocation(coordinates)
    }

    if useCanadian {
      return try await getCanadianWeatherAlerts(coordinates: coordinates)
    } else {
      return try await getBrightskyAlerts(coordinates: coordinates)
    }
  }

  private func isCanadianLocation(_ coordinates: CLLocationCoordinate2D) -> Bool {
    guard coordinates.latitude <= 84.0,
      coordinates.longitude >= -141.0,
      coordinates.longitude <= -52.0
    else {
      return false
    }

    let minimumLatitude = coordinates.longitude < -95.0 ? 49.0 : 45.0
    return coordinates.latitude >= minimumLatitude
  }

  private func getBrightskyAlerts(coordinates: CLLocationCoordinate2D) async throws -> AlertResponse
  {
    let outboundCoordinates = LocationService.outboundCoordinate(coordinates)
    let response = try await brightsky.getAlerts(
      .init(
        query: .init(
          lat: outboundCoordinates.latitude,
          lon: outboundCoordinates.longitude
        )
      ))

    switch response {
    case let .ok(response):
      switch response.body {
      case .json(let result):
        return .brightsky(result)
      }
    case .undocumented:
      return .brightsky(.init())
    }
  }

  private func getCanadianWeatherAlerts(coordinates: CLLocationCoordinate2D) async throws
    -> AlertResponse
  {
    let outboundCoordinates = LocationService.outboundCoordinate(coordinates)
    let response = try await canadaWeather.getCanadianWeatherAlerts(
      .init(
        path: .init(
          latitude: outboundCoordinates.latitude,
          longitude: outboundCoordinates.longitude
        )
      ))

    switch response {
    case let .ok(response):
      switch response.body {
      case .json(let result):
        return .canadian(result)
      }
    case .undocumented:
      return .canadian([])
    }
  }

  func getGeocodeSearchResult(name: String) async throws -> Components.Schemas.SearchResponse {
    let appLanguage = Locale.current.language.languageCode?.identifier ?? "de"
    let response = try await openMeteoGeo.search(
      .init(
        query: .init(
          name: name, language: Operations.search.Input.Query.languagePayload(rawValue: appLanguage)
        )
      ))
    switch response {
    case let .ok(response):
      switch response.body {
      case .json(let result):
        return result
      }
    case .undocumented:
      return .init()
    }
  }

  /// Per-location precipitation timeline (observations + nowcast, mm/h) from
  /// oscar-server's `/radar/series`. Auto-routes DWD inside Germany / OPERA
  /// elsewhere in Europe. Hand-written (oscar-server is not part of the
  /// generated OpenAPI client).
  ///
  /// Returns `nil` only when the server *successfully* reports no coverage for
  /// this location (204/404). Any real failure — transport error, cancellation,
  /// unexpected status, or a decode failure — is thrown, so callers can tell
  /// "no rain here" apart from "couldn't fetch" and avoid discarding good data.
  func getRadarSeries(coordinates: CLLocationCoordinate2D) async throws
    -> PrecipSeriesResponse?
  {
    let outboundCoordinates = LocationService.outboundCoordinate(coordinates)
    guard
      let url = URL(
        string:
          "\(radarBaseURL)/radar/series?lat=\(outboundCoordinates.latitude)&lon=\(outboundCoordinates.longitude)"
      )
    else { return nil }

    var request = URLRequest(url: url)
    request.addAPIContactIdentity()
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    if http.statusCode == 204 || http.statusCode == 404 { return nil }
    guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
    return try JSONDecoder().decode(PrecipSeriesResponse.self, from: data)
  }

  func getRainViewerMaps() async throws -> Components.Schemas.RainViewerResponse {
    let fallbackResponse: Components.Schemas.RainViewerResponse = .init(
      version: "2.0",
      generated: Int(Date().timeIntervalSince1970),
      host: "",
      radar: .init(past: [], nowcast: []),
      satellite: .init(infrared: [])
    )

    let response = try await rainViewer.getRainViewerMaps(.init())

    switch response {
    case let .ok(response):
      switch response.body {
      case .json(let result):
        return result
      }
    case .undocumented:
      return fallbackResponse
    }
  }
}
