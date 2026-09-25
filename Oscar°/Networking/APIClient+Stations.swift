import CoreLocation
import Foundation

/// oscar-server `/stations/nearby` rows, shown as `ForEach` chips and cards.
extension Components.Schemas.NearbyStation: Identifiable {}

extension APIClient {
  /// The nearest stations with fresh readings, nearest first. Empty outside
  /// oscar-server's station coverage (Europe), without a request.
  func getNearbyStations(coordinates: CLLocationCoordinate2D) async throws
    -> [Components.Schemas.NearbyStation]
  {
    let europe = (26.0...81.0).contains(coordinates.latitude) && (-32.0...46.0).contains(coordinates.longitude)
    guard europe else { return [] }
    let outbound = LocationService.outboundCoordinate(coordinates)
    let output = try await oscarServer.getNearbyStations(
      .init(query: .init(lat: outbound.latitude, lon: outbound.longitude)))
    switch output {
    case .ok(let ok): return try ok.body.json.stations
    case .undocumented: throw URLError(.badServerResponse)
    }
  }
}
