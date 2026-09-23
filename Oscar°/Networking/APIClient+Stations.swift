import CoreLocation
import Foundation

/// A nearby weather station from oscar-server `/stations/nearby`. Values are SI as
/// served (°C, %, m/s, degrees, hPa, mm); `StationUnits` converts for display.
struct WeatherStation: Identifiable, Equatable {
  let id: String
  let name: String
  /// "esoh" (EUMETNET) or "dwd".
  let source: String
  let distanceKm: Double
  let bearing: Double
  let lastReportAt: Date
  let current: StationReading
  let precipitation24h: Double?
  /// Oldest first.
  let history: [StationReading]
}

struct StationReading: Equatable {
  let time: Date
  let temperature: Double?
  let humidity: Double?
  let dewPoint: Double?
  let windSpeed: Double?
  let windDirection: Double?
  let windGust: Double?
  let pressure: Double?
  let precipitation: Double?
  /// Window of `precipitation`, ending at `time`.
  let precipitationMinutes: Int?
  /// Forecast WMO code; `current` only, and only where the station reports weather or clouds.
  var weatherCode: Int? = nil
}

extension StationReading {
  init?(_ payload: Components.Schemas.StationReading) {
    guard let time = PrecipSeriesDate.parse(payload.time) else { return nil }
    self.time = time
    temperature = payload.temperature_c
    humidity = payload.humidity_pct
    dewPoint = payload.dew_point_c
    windSpeed = payload.wind_speed_ms
    windDirection = payload.wind_direction_deg
    windGust = payload.wind_gust_ms
    pressure = payload.pressure_hpa
    precipitation = payload.precipitation_mm
    precipitationMinutes = payload.precipitation_period_min
    weatherCode = payload.weather_code
  }
}

extension WeatherStation {
  init?(_ payload: Components.Schemas.NearbyStation) {
    guard let lastReportAt = PrecipSeriesDate.parse(payload.last_report_at),
      let current = StationReading(payload.current)
    else { return nil }
    id = payload.id
    name = payload.name
    source = payload.source
    distanceKm = payload.distance_km
    bearing = payload.bearing_deg
    self.lastReportAt = lastReportAt
    self.current = current
    precipitation24h = payload.precipitation_24h_mm
    history = payload.history.compactMap(StationReading.init)
  }
}

extension APIClient {
  /// The nearest stations with fresh readings, nearest first. Empty outside
  /// oscar-server's station coverage (Europe), without a request.
  func getNearbyStations(coordinates: CLLocationCoordinate2D) async throws -> [WeatherStation] {
    let europe = (26.0...81.0).contains(coordinates.latitude) && (-32.0...46.0).contains(coordinates.longitude)
    guard europe else { return [] }
    let outbound = LocationService.outboundCoordinate(coordinates)
    let output = try await oscarServer.getNearbyStations(
      .init(query: .init(lat: outbound.latitude, lon: outbound.longitude)))
    switch output {
    case .ok(let ok):
      return try ok.body.json.stations.compactMap(WeatherStation.init)
    case .undocumented:
      throw URLError(.badServerResponse)
    }
  }
}
