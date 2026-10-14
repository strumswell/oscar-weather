import CoreLocation
import Foundation

extension APIClient {
  func getRadarSeries(coordinates: CLLocationCoordinate2D) async throws
    -> PrecipSeriesResponse?
  {
    let outboundCoordinates = LocationService.outboundCoordinate(coordinates)
    let output = try await oscarServer.getRadarSeries(
      .init(query: .init(lat: outboundCoordinates.latitude, lon: outboundCoordinates.longitude)))
    switch output {
    case .ok(let ok):
      return try PrecipSeriesResponse(payload: try ok.body.json)
    case .undocumented(let statusCode, _):
      if statusCode == 204 || statusCode == 404 { return nil }
      throw URLError(.badServerResponse)
    }
  }

  func getCloudSeries(coordinates: CLLocationCoordinate2D) async throws
    -> CloudSeriesResponse?
  {
    let outboundCoordinates = LocationService.outboundCoordinate(coordinates)
    let output = try await oscarServer.getCloudSeries(
      .init(query: .init(lat: outboundCoordinates.latitude, lon: outboundCoordinates.longitude)))
    switch output {
    case .ok(let ok):
      return try CloudSeriesResponse(payload: try ok.body.json)
    case .undocumented(let statusCode, _):
      if statusCode == 204 || statusCode == 404 || statusCode == 503 { return nil }
      throw URLError(.badServerResponse)
    }
  }

  func getPressureIsolines(framesEndpoint: String, frameKey: String) async throws -> Data {
    guard let url = URL(string: "\(radarBaseURL)/\(framesEndpoint)/\(frameKey)/pressure/isolines")
    else { throw URLError(.badURL) }
    var request = URLRequest(url: url)
    request.addAPIContactIdentity()
    let (data, http) = try await Self.fetchWithRetry(request)
    guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
    return data
  }
}

// MARK: - Wire payload → domain mapping

extension PrecipSeriesResponse {
  init(payload: Components.Schemas.PrecipSeriesResponse) throws {
    self.init(
      source: payload.source,
      unit: payload.unit,
      latitude: payload.latitude,
      longitude: payload.longitude,
      series: try payload.series.map { point in
        guard let date = PrecipSeriesDate.parse(point.timestamp) else {
          throw URLError(.cannotDecodeContentData)
        }
        return PrecipPoint(
          timestamp: date,
          precipitation: point.precipitation,
          isForecast: point.is_forecast ?? false)
      },
      generatedAt: payload.generated_at,
      lastObservedAt: payload.last_observed_at,
      forecastHorizon: payload.forecast_horizon)
  }
}

extension CloudSeriesResponse {
  init(payload: Components.Schemas.CloudSeriesResponse) throws {
    self.init(
      source: payload.source,
      latitude: payload.latitude,
      longitude: payload.longitude,
      series: try payload.series.map { point in
        guard let date = PrecipSeriesDate.parse(point.timestamp) else {
          throw URLError(.cannotDecodeContentData)
        }
        return CloudPoint(timestamp: date, value: point.value, isForecast: point.is_forecast ?? false)
      },
      generatedAt: payload.generated_at,
      forecastHorizon: payload.forecast_horizon)
  }
}
