import CoreLocation
import Foundation

extension Components.Schemas.Webcam: Identifiable {}

extension APIClient {
  /// Active webcams in a box, most popular first (at most 50). The server grows the box to
  /// a 0.5° grid and refuses spans over 15°. Image URLs expire after 10 min: never store them.
  func getWebcams(north: Double, south: Double, east: Double, west: Double) async throws
    -> [Components.Schemas.Webcam]
  {
    let output = try await oscarServer.getWebcams(
      .init(query: .init(north: north, south: south, east: east, west: west)))
    switch output {
    case .ok(let ok): return try ok.body.json.webcams
    case .undocumented: throw URLError(.badServerResponse)
    }
  }

  /// The webcams within `radiusKm` of a place, nearest first.
  func getWebcams(near coordinates: CLLocationCoordinate2D, radiusKm: Double = 30) async throws
    -> [Components.Schemas.Webcam]
  {
    let center = LocationService.outboundCoordinate(coordinates)
    let dLat = radiusKm / 111.2
    let dLon = radiusKm / (111.2 * max(cos(center.latitude * .pi / 180), 0.01))
    let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
    func km(_ webcam: Components.Schemas.Webcam) -> Double {
      here.distance(from: CLLocation(latitude: webcam.latitude, longitude: webcam.longitude)) / 1000
    }
    return try await getWebcams(
      north: min(center.latitude + dLat, 90), south: max(center.latitude - dLat, -90),
      east: min(center.longitude + dLon, 180), west: max(center.longitude - dLon, -180)
    )
    .filter { km($0) <= radiusKm }
    .sorted { km($0) < km($1) }
  }
}
