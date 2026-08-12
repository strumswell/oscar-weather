import CoreLocation
import Foundation

enum AlertResponse {
  case canadian(Operations.getCanadianWeatherAlerts.Output.Ok.Body.jsonPayload)
  case oscar(OscarPointAlertsResponse)
}

/// oscar-server `/weather-alerts/point` response — hand-written like the other
/// oscar-server calls (the server is not part of the generated OpenAPI client).
/// Used for US locations, where the server ingests NWS alerts; `source` drives
/// the attribution line ("nws" → NOAA / National Weather Service).
struct OscarPointAlertsResponse {
  let alertCount: Int
  let alerts: [OscarPointAlert]

  /// The "no active warnings" placeholder used before the first fetch and after
  /// a failed one — alerts are supplementary and must never block a refresh.
  static let empty = OscarPointAlertsResponse(alertCount: 0, alerts: [])

  /// Maps the generated wire payload. oscar-server dates are ISO-8601 with
  /// fractional seconds; the plain variant is accepted too, and an unparseable
  /// date degrades to nil (the UI hides the times) instead of dropping alerts.
  init(payload: Components.Schemas.OscarPointAlertsResponse) {
    alertCount = payload.alertCount
    alerts = payload.alerts.map { alert in
      OscarPointAlert(
        alertId: alert.alertId,
        source: alert.source,
        senderName: alert.senderName,
        event: alert.event,
        severity: alert.severity,
        urgency: alert.urgency,
        certainty: alert.certainty,
        responseType: alert.responseType,
        onsetAt: alert.onsetAt.flatMap(OscarAlertDate.parse),
        expiresAt: alert.expiresAt.flatMap(OscarAlertDate.parse),
        headline: alert.headline,
        description: alert.description,
        instruction: alert.instruction)
    }
  }

  private init(alertCount: Int, alerts: [OscarPointAlert]) {
    self.alertCount = alertCount
    self.alerts = alerts
  }
}

private enum OscarAlertDate {
  nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()
  nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

  static func parse(_ string: String) -> Date? {
    fractional.date(from: string) ?? plain.date(from: string)
  }
}

struct OscarPointAlert {
  let alertId: String
  let source: String
  /// Originating national weather service for Meteoalarm alerts ("Météo-France") —
  /// the hub only aggregates, so attribution shows both. nil from older servers
  /// and for natively ingested sources.
  let senderName: String?
  let event: String
  let severity: String
  let urgency: String
  let certainty: String
  let responseType: String?
  let onsetAt: Date?
  let expiresAt: Date?
  let headline: String?
  let description: String?
  let instruction: String?
}

extension APIClient {
  func getAlerts(
    coordinates: CLLocationCoordinate2D,
    countryCode: String? = nil
  ) async throws -> AlertResponse {
    let useCanadian: Bool
    let useUnitedStates: Bool
    let useTaiwan: Bool
    let useMeteoalarm: Bool
    if let countryCode {
      useCanadian = countryCode == "CA"
      useUnitedStates = countryCode == "US"
      useTaiwan = countryCode == "TW"
      useMeteoalarm = Self.meteoalarmCountryCodes.contains(countryCode)
    } else {
      useCanadian = isCanadianLocation(coordinates)
      useUnitedStates = !useCanadian && isUnitedStatesLocation(coordinates)
      useTaiwan = !useCanadian && !useUnitedStates && isTaiwanLocation(coordinates)
      useMeteoalarm =
        !useCanadian && !useUnitedStates && !useTaiwan && isMeteoalarmLocation(coordinates)
    }

    if useCanadian {
      return try await getCanadianWeatherAlerts(coordinates: coordinates)
    } else if useUnitedStates || useTaiwan || useMeteoalarm {
      // NWS (US), CWA (Taiwan), DWD (Germany) and Meteoalarm (rest of Europe)
      // warnings are all served by oscar-server on the same source-tagged
      // endpoint; the response's `source` drives attribution.
      return try await getOscarWeatherAlerts(coordinates: coordinates)
    } else {
      // No warning source for this location — report "none" without a fetch.
      return .oscar(.empty)
    }
  }

  /// ISO codes of the countries whose warnings oscar-server ingests: the EUMETNET
  /// Meteoalarm members plus Germany (DWD CAP feed, ingested natively); note the
  /// UK's ISO code is "GB" even though Meteoalarm slugs it "uk".
  private static let meteoalarmCountryCodes: Set<String> = [
    "AT", "BA", "BE", "BG", "CH", "CY", "CZ", "DE", "DK", "EE", "ES", "FI", "FR", "GB",
    "GR", "HR", "HU", "IE", "IL", "IS", "IT", "LT", "LU", "LV", "MD", "ME", "MK", "MT",
    "NL", "NO", "PL", "PT", "RO", "RS", "SE", "SI", "SK", "UA",
  ]

  /// European warning coverage for saved cities, which reach us without a country
  /// code: greater Europe (Azores/Iceland to Ukraine, Canaries to the North Cape)
  /// plus Israel. Germany falls inside this box and resolves to its native DWD
  /// alerts on the same oscar-server endpoint.
  private func isMeteoalarmLocation(_ coordinates: CLLocationCoordinate2D) -> Bool {
    let lat = coordinates.latitude
    let lon = coordinates.longitude
    let europe = lat >= 27.0 && lat <= 72.0 && lon >= -32.0 && lon <= 45.0
    let israel = lat >= 29.4 && lat <= 33.4 && lon >= 34.2 && lon <= 35.9
    return europe || israel
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

  /// NWS alert coverage boxes: CONUS, Alaska, Hawaii, Puerto Rico/USVI, and
  /// Guam/Northern Marianas. Only consulted after the Canada check, so the
  /// shared-border strip keeps resolving to Environment Canada as before.
  private func isUnitedStatesLocation(_ coordinates: CLLocationCoordinate2D) -> Bool {
    let lat = coordinates.latitude
    let lon = coordinates.longitude
    let conus = lat >= 24.3 && lat <= 49.5 && lon >= -125.0 && lon <= -66.5
    let alaska = lat >= 51.0 && lat <= 72.0 && lon >= -170.0 && lon <= -129.5
    let hawaii = lat >= 18.5 && lat <= 22.5 && lon >= -160.6 && lon <= -154.5
    let caribbean = lat >= 17.4 && lat <= 18.6 && lon >= -68.0 && lon <= -64.3
    let pacific = lat >= 12.9 && lat <= 20.6 && lon >= 144.5 && lon <= 146.1
    return conus || alaska || hawaii || caribbean || pacific
  }

  /// CWA (Taiwan) alert coverage: the main island plus its outlying county groups
  /// (Penghu, Kinmen, Matsu). Mirrors `RadarRegion.taiwan`'s coverage box and is only
  /// consulted after the Canada/US checks.
  private func isTaiwanLocation(_ coordinates: CLLocationCoordinate2D) -> Bool {
    let lat = coordinates.latitude
    let lon = coordinates.longitude
    return lat >= 20.5 && lat <= 26.5 && lon >= 118.0 && lon <= 124.0
  }

  /// Active severe-weather alerts at a point from oscar-server
  /// (`/weather-alerts/point`, NWS-sourced for US locations). Geometry is
  /// skipped — the badge and detail list never render it, and US multi-zone
  /// alerts can carry hundreds of KB of polygon rings.
  private func getOscarWeatherAlerts(coordinates: CLLocationCoordinate2D) async throws
    -> AlertResponse
  {
    .oscar(try await getOscarPointAlerts(coordinates: coordinates))
  }

  /// The raw `/weather-alerts/point` response. Also the map's tap-through
  /// resolver: the `/area` overlay serves DISSOLVED severity shapes without
  /// per-alert text, so a polygon tap asks this endpoint what is active at the
  /// tapped coordinate.
  func getOscarPointAlerts(coordinates: CLLocationCoordinate2D) async throws
    -> OscarPointAlertsResponse
  {
    let outboundCoordinates = LocationService.outboundCoordinate(coordinates)
    let language = Locale.current.language.languageCode?.identifier == "de" ? "de" : "en"
    let output = try await oscarServer.getOscarPointAlerts(
      .init(
        query: .init(
          lat: outboundCoordinates.latitude,
          lon: outboundCoordinates.longitude,
          lang: language,
          includeGeometry: false
        )))
    switch output {
    case .ok(let ok):
      return OscarPointAlertsResponse(payload: try ok.body.json)
    case .undocumented:
      throw URLError(.badServerResponse)
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

  /// Active severe-weather warning polygons for a map viewport box, as a raw GeoJSON
  /// FeatureCollection from oscar-server — handed straight to MapLibre's shape
  /// sources. Callers pass the padded visible bounds (see `alertRequestBox` in the
  /// map coordinator); the box must stay inside the endpoint's 25°×40° guard.
  /// Deliberately NOT `dissolve=true`: warning outlines are built independently
  /// per alert, so the server's parity dissolve shreds real-world data (slivers,
  /// overlap punch-outs) — the per-alert mesh is the honest rendering.
  func getWeatherAlertPolygons(
    minLat: Double, maxLat: Double, minLon: Double, maxLon: Double
  ) async throws -> Data {
    let language = Locale.current.language.languageCode?.identifier == "de" ? "de" : "en"
    guard
      let url = URL(
        string:
          "\(radarBaseURL)/weather-alerts/area?minLat=\(minLat)&minLon=\(minLon)&maxLat=\(maxLat)&maxLon=\(maxLon)&lang=\(language)"
      )
    else { throw URLError(.badURL) }

    var request = URLRequest(url: url)
    request.addAPIContactIdentity()
    let (data, http) = try await Self.fetchWithRetry(request)
    guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
    return data
  }
}
