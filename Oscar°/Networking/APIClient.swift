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

let radarBaseURL: String = {
    #if DEBUG
    if let override = UserDefaults.standard.string(forKey: "radarBaseURL"),
       !override.isEmpty {
        return override.hasSuffix("/") ? String(override.dropLast()) : override
    }
    #endif
    return "https://server.oscars.love"
}()

final class APIClient: Sendable {
  static let shared = APIClient()

  let openMeteo: Client
  let openMeteoAqi: Client
  let openMeteoGeo: Client
  let openMeteoArchive: Client
  let canadaWeather: Client
  let oscarServer: Client
  let oscarServerSnapshot: Client

  init() {
    openMeteo = APIClient.get(
      url: Self.serverURL(Servers.server1),
      prepending: [ForecastSanitizingMiddleware()]
    )
    openMeteoAqi = APIClient.get(url: Self.serverURL(Servers.server2))
    openMeteoGeo = APIClient.get(url: Self.serverURL(Servers.server3))
    openMeteoArchive = APIClient.get(url: Self.serverURL(Servers.server5))
    canadaWeather = APIClient.get(url: Self.serverURL(Servers.server4))
    oscarServer = Client(
      serverURL: URL(string: radarBaseURL) ?? Self.serverURL(Servers.server6),
      configuration: Self.oscarServerConfiguration,
      transport: URLSessionTransport(),
      middlewares: Self.stagingMiddlewares + [
        UsageCountingMiddleware(),
        ContactIdentityMiddleware(),
        RetryingMiddleware(
          signals: [.code(429), .range(500..<600), .errorThrown],
          policy: .upToAttempts(count: 3),
          delay: .exponentialWithJitter(base: 0.5, maxSeconds: 8)
        ),
      ]
    )
    let snapshotConfiguration = URLSessionConfiguration.default
    snapshotConfiguration.timeoutIntervalForRequest = 20
    oscarServerSnapshot = Client(
      serverURL: URL(string: radarBaseURL) ?? Self.serverURL(Servers.server6),
      configuration: Self.oscarServerConfiguration,
      transport: URLSessionTransport(
        configuration: .init(session: URLSession(configuration: snapshotConfiguration))),
      middlewares: Self.stagingMiddlewares + [ContactIdentityMiddleware()]
    )
  }


  private static func serverURL(_ make: () throws -> URL) -> URL {
    do {
      return try make()
    } catch {
      fatalError("Failed to construct OpenAPI server URL: \(error.localizedDescription)")
    }
  }

  nonisolated(unsafe) static var stagingMiddlewares: [any ClientMiddleware] = []
  nonisolated(unsafe) static var stagedFetch: (@Sendable (URLRequest) -> (Data, HTTPURLResponse)?)?

  class func get(url: URL, prepending middlewares: [any ClientMiddleware] = []) -> Client {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = OpenMeteoCustomer.timeout
    return Client(
      serverURL: url,
      transport: URLSessionTransport(configuration: .init(session: URLSession(configuration: configuration))),
      middlewares: Self.stagingMiddlewares + middlewares + [
        CachingMiddleware(cacheTime: 60),
        UsageCountingMiddleware(),
        ContactIdentityMiddleware(),
        RetryingMiddleware(
          signals: [.code(429), .range(500..<600), .errorThrown],
          policy: .upToAttempts(count: 3),
          delay: .exponentialWithJitter(base: 0.5, maxSeconds: 8)
        ),
        OpenMeteoCustomerMiddleware(),
      ]
    )
  }

  func getForecast(
    coordinates: CLLocationCoordinate2D,
    forecastDays: Operations.getForecast.Input.Query.forecast_daysPayload? = ._14,
    hourly: [Operations.getForecast.Input.Query.hourlyPayloadPayload]? = nil
  ) async throws -> Operations.getForecast.Output.Ok.Body.jsonPayload {
    var forecast = try await fetchForecast(coordinates: coordinates, forecastDays: forecastDays, hourly: hourly)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = forecast.locationTimeZone
    if let times = forecast.daily?.time {
      forecast.daily?.time = times.map {
        calendar.startOfDay(for: Date(timeIntervalSince1970: $0 + 43_200)).timeIntervalSince1970
      }
    }
    return forecast
  }

  private func fetchForecast(
    coordinates: CLLocationCoordinate2D,
    forecastDays: Operations.getForecast.Input.Query.forecast_daysPayload?,
    hourly: [Operations.getForecast.Input.Query.hourlyPayloadPayload]?
  ) async throws -> Operations.getForecast.Output.Ok.Body.jsonPayload {
    let outboundCoordinates = LocationService.outboundCoordinate(coordinates)

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
      .windgusts_10m, .cloudcover_low, .cloudcover_mid, .cloudcover_high,
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
        .cloudcover, .cloudcover_low, .cloudcover_mid, .cloudcover_high, .temperature,
        .wind_direction_10m, .weathercode, .windspeed, .precipitation, .is_day,
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

    if modelPreference != .bestMatch {
      query.models = Operations.getForecast.Input.Query.modelsPayload(rawValue: modelPreference.apiValue)
    }
    else if coordinates.country() == .spain || coordinates.country() == .portugal {
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
        throw URLError(.badServerResponse)
      }

      query.models = .best_match
      query.forecast_days = ._14

      let bestMatchResponse = try await openMeteo.getForecast(.init(query: query))

      switch bestMatchResponse {
      case let .ok(response):
        switch response.body {
        case .json(let result):
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

          let startIndex = iconDaily.time.count
          guard bestMatchDaily.time.count > startIndex else { return iconForecast }
          iconDaily.time.append(contentsOf: bestMatchDaily.time.dropFirst(startIndex))
          iconDaily.temperature_2m_max?.append(contentsOf: maxTemps.dropFirst(startIndex))
          iconDaily.temperature_2m_min?.append(contentsOf: minTemps.dropFirst(startIndex))
          iconDaily.precipitation_sum?.append(contentsOf: precip.dropFirst(startIndex))
          iconDaily.precipitation_probability_max?.append(
            contentsOf: precipProb.dropFirst(startIndex))
          iconDaily.weathercode?.append(contentsOf: codes.dropFirst(startIndex))
          iconDaily.sunrise?.append(contentsOf: sunrises.dropFirst(startIndex))
          iconDaily.sunset?.append(contentsOf: sunsets.dropFirst(startIndex))

          iconForecast.daily = iconDaily
          return iconForecast
        }
      case .badRequest(_), .undocumented(statusCode: _, _):
        return iconForecast
      }
    }

    let response = try await openMeteo.getForecast(.init(query: query))

    switch response {
    case let .ok(response):
      switch response.body {
      case .json(let result):
        return result
      }
    case .badRequest(_), .undocumented(statusCode: _, _):
      if modelPreference != .bestMatch,
        let fallback = try await fallbackToBestMatch(query: query, failedModel: modelPreference)
      {
        return fallback
      }
      throw URLError(.badServerResponse)
    }
  }

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
    Task { @MainActor in
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
      throw URLError(.badServerResponse)
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
          "temperature_2m_max",
          "temperature_2m_min",
          "precipitation_sum",
          "snowfall_sum",
          "wind_speed_10m_max",
          "weather_code",
          "cloud_cover_mean",
        ].joined(separator: ",")
      ),
      URLQueryItem(name: "models", value: model.rawValue),
      URLQueryItem(name: "temperature_unit", value: SettingService.resolvedTemperatureUnit),
      URLQueryItem(name: "wind_speed_unit", value: windSpeedUnit.apiRawValue),
      URLQueryItem(name: "precipitation_unit", value: SettingService.resolvedPrecipitationUnit),
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

    let (data, httpResponse) = try await Self.fetchWithRetry(request)
    guard (200...299).contains(httpResponse.statusCode) else {
      throw URLError(.badServerResponse)
    }

    let decoded = try decoder.decode(DailyEnsembleForecastResponse.self, from: data)
    await DailyEnsembleForecastCache.shared.set(data, for: cacheKey)
    return decoded
  }

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
      throw URLError(.badServerResponse)
    }
  }

  static func fetchWithRetry(
    _ request: URLRequest, attempts: Int = 3
  ) async throws -> (Data, HTTPURLResponse) {
    if let staged = Self.stagedFetch?(request) { return staged }
    var lastError: Error = URLError(.unknown)
    for attempt in 0..<attempts {
      if attempt > 0 {
        let base = 0.5 * pow(2, Double(attempt - 1))
        try await Task.sleep(for: .seconds(min(8, base) * Double.random(in: 0.5...1.5)))
      }
      do {
        let (data, response) = try await OpenMeteoCustomer.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 429 || (500..<600).contains(http.statusCode) {
          lastError = URLError(.badServerResponse)
          continue
        }
        return (data, http)
      } catch is CancellationError {
        throw CancellationError()
      } catch let error as URLError where error.code == .cancelled {
        throw error
      } catch {
        lastError = error
      }
    }
    throw lastError
  }
}
