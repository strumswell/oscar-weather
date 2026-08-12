import CoreLocation
import Foundation

extension APIClient {
  /// Noteworthy meteor showers for the active Oscar location. The backend owns
  /// observing-date and astronomical visibility logic; coordinates follow the
  /// same approximately 100 m rounding contract as the weather requests.
  func getActiveMeteorShowers(
    coordinates: CLLocationCoordinate2D,
    countryCode: String
  ) async throws -> MeteorShowerResponse {
    let request = try Self.activeMeteorShowersRequest(
      coordinates: coordinates,
      countryCode: countryCode
    )
    let (data, response) = try await Self.fetchWithRetry(request, attempts: 1)
    guard (200...299).contains(response.statusCode) else {
      throw URLError(.badServerResponse)
    }
    return try MeteorShowerResponse.decode(from: data)
  }

  /// Pure request builder used by the transport and unit tests.
  static func activeMeteorShowersRequest(
    coordinates: CLLocationCoordinate2D,
    countryCode: String
  ) throws -> URLRequest {
    let normalizedCountryCode = countryCode
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
    guard normalizedCountryCode.unicodeScalars.count == 2,
          normalizedCountryCode.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else {
      throw URLError(.badURL)
    }

    guard var components = URLComponents(
      string: "https://astro.oscars.love/v1/meteor-showers/active"
    ) else {
      throw URLError(.badURL)
    }
    let outboundCoordinates = LocationService.outboundCoordinate(coordinates)
    components.queryItems = [
      URLQueryItem(name: "lat", value: String(outboundCoordinates.latitude)),
      URLQueryItem(name: "lon", value: String(outboundCoordinates.longitude)),
      URLQueryItem(name: "country_code", value: normalizedCountryCode),
    ]
    guard let url = components.url else { throw URLError(.badURL) }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 10
    request.addAPIContactIdentity()
    return request
  }
}
