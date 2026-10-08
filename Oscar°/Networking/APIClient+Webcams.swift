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
}
