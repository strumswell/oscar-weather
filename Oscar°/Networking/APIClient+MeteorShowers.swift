import CoreLocation
import Foundation

extension APIClient {
  /// Tonight's meteor observing conditions for the active Oscar location from
  /// oscar-server. The server owns the catalogue, astronomy and weather rating;
  /// coordinates follow the same approximately 100 m rounding contract as the
  /// weather requests.
  func getMeteorShowers(coordinates: CLLocationCoordinate2D) async throws -> MeteorShowerResponse {
    let request = try Self.meteorShowersRequest(coordinates: coordinates)
    let (data, response) = try await Self.fetchWithRetry(request)
    guard (200...299).contains(response.statusCode) else {
      throw URLError(.badServerResponse)
    }
    return try MeteorShowerResponse.decode(from: data)
  }

  /// Pure request builder used by the transport and unit tests.
  static func meteorShowersRequest(
    coordinates: CLLocationCoordinate2D,
    baseURL: String = radarBaseURL
  ) throws -> URLRequest {
    guard CLLocationCoordinate2DIsValid(coordinates),
          var components = URLComponents(string: baseURL + "/astro/meteors") else {
      throw URLError(.badURL)
    }
    let outboundCoordinates = LocationService.outboundCoordinate(coordinates)
    components.queryItems = [
      URLQueryItem(name: "lat", value: String(outboundCoordinates.latitude)),
      URLQueryItem(name: "lon", value: String(outboundCoordinates.longitude)),
    ]
    guard let url = components.url else { throw URLError(.badURL) }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 10
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.addAPIContactIdentity()
    return request
  }
}
