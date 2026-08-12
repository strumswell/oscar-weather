import CoreLocation
import Foundation

extension APIClient {
  /// Per-location precipitation timeline (observations + nowcast, mm/h) from
  /// oscar-server's `/radar/series`. Auto-routes DWD inside Germany / OPERA
  /// elsewhere in Europe.
  ///
  /// Returns `nil` only when the server *successfully* reports no coverage for
  /// this location (204/404). Any real failure — transport error, cancellation,
  /// unexpected status, or a decode failure — is thrown, so callers can tell
  /// "no rain here" apart from "couldn't fetch" and avoid discarding good data.
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

  /// Per-location satellite cloudiness series (`/clouds/meteosat/series`) — the
  /// head view's trend annotation. nil = outside the disk or clouds not ready
  /// (404/503); both simply mean "no annotation".
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

  /// Isobar GeoJSON for one model frame (`/{framesEndpoint}/{frameKey}/pressure/isolines`):
  /// MSLP isolines as MultiLineStrings plus H/T pressure-center points. One of the two
  /// GeoJSON passthroughs deliberately kept off the generated client — MapLibre parses
  /// the raw bytes, and the freeform JSON container would box every coordinate.
  /// `framesEndpoint` is the layer's frames path ("models/icon/frames") — kept a
  /// string because WeatherTileLayer isn't compiled into every target this file is.
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
  /// Maps the generated wire payload, parsing timestamps with the same tolerant
  /// ISO8601 handling as before; an unparseable timestamp throws, matching the
  /// old decode-failure behavior (callers keep last-known-good).
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
