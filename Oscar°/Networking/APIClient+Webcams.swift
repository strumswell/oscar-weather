import Foundation

extension Components.Schemas.Webcam: Identifiable {}

extension APIClient {
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
