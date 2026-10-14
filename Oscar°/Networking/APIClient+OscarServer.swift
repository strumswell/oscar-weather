import Foundation
import OpenAPIRuntime

// MARK: - oscar-server accessors (generated client)

extension APIClient {
  private static let assetByteLimit = 64 * 1024 * 1024

  static let oscarServerConfiguration = Configuration(dateTranscoder: OscarServerDateTranscoder())

  enum ServerProfile {
    case standard
    case snapshot
  }

  private func client(for profile: ServerProfile) -> Client {
    switch profile {
    case .standard: oscarServer
    case .snapshot: oscarServerSnapshot
    }
  }

  // MARK: Frames

  func radarFrames(region: String, profile: ServerProfile = .standard) async throws
    -> Components.Schemas.RadarFramesResponse
  {
    switch try await client(for: profile).getRadarFrames(.init(path: .init(region: region))) {
    case .ok(let ok): return try ok.body.json
    case .undocumented: throw URLError(.badServerResponse)
    }
  }

  func cloudFrames() async throws -> Components.Schemas.RadarFramesResponse? {
    switch try await oscarServer.getCloudFrames(.init()) {
    case .ok(let ok): return try ok.body.json
    case .undocumented(let statusCode, _):
      if statusCode == 404 || statusCode == 503 { return nil }
      throw URLError(.badServerResponse)
    }
  }

  func modelFrames(model: String, profile: ServerProfile = .standard) async throws
    -> Components.Schemas.ModelFramesResponse
  {
    switch try await client(for: profile).getModelFrames(.init(path: .init(model: model))) {
    case .ok(let ok): return try ok.body.json
    case .undocumented: throw URLError(.badServerResponse)
    }
  }

  // MARK: Motion

  func radarMotion(region: String, profile: ServerProfile = .standard) async throws
    -> Components.Schemas.MotionResponse
  {
    switch try await client(for: profile).getRadarMotion(.init(path: .init(region: region))) {
    case .ok(let ok): return try ok.body.json
    case .undocumented: throw URLError(.badServerResponse)
    }
  }

  func cloudMotion() async throws -> Components.Schemas.MotionResponse {
    switch try await oscarServer.getCloudMotion(.init()) {
    case .ok(let ok): return try ok.body.json
    case .undocumented: throw URLError(.badServerResponse)
    }
  }

  func modelMotion(model: String) async throws -> Components.Schemas.MotionResponse {
    switch try await oscarServer.getModelMotion(.init(path: .init(model: model))) {
    case .ok(let ok): return try ok.body.json
    case .undocumented: throw URLError(.badServerResponse)
    }
  }

  // MARK: Value grids / tiles / palettes (binary WebP & RGBA assets)

  func radarGrid(region: String, key: String) async throws -> Data? {
    let output = try await oscarServer.getRadarGrid(
      .init(path: .init(region: region, key: key)))
    switch output {
    case .ok(let ok):
      return try await Data(collecting: ok.body.image_webp, upTo: Self.assetByteLimit)
    case .undocumented(let statusCode, _):
      if statusCode == 404 { return nil }
      throw URLError(.badServerResponse)
    }
  }

  func cloudGrid(key: String) async throws -> Data {
    switch try await oscarServer.getCloudGrid(.init(path: .init(key: key))) {
    case .ok(let ok):
      return try await Data(collecting: ok.body.image_webp, upTo: Self.assetByteLimit)
    case .undocumented: throw URLError(.badServerResponse)
    }
  }

  func modelGrid(model: String, key: String, variable: String) async throws -> Data? {
    let output = try await oscarServer.getModelGrid(
      .init(path: .init(model: model, key: key, variable: variable)))
    switch output {
    case .ok(let ok):
      return try await Data(collecting: ok.body.image_webp, upTo: Self.assetByteLimit)
    case .undocumented(let statusCode, _):
      if statusCode == 404 { return nil }
      throw URLError(.badServerResponse)
    }
  }

  func radarTile(
    region: String, key: String, z: Int, x: Int, y: Int, profile: ServerProfile = .standard
  ) async throws -> Data {
    let output = try await client(for: profile).getRadarTile(
      .init(path: .init(region: region, key: key, z: z, x: x, y: y)))
    switch output {
    case .ok(let ok):
      return try await Data(collecting: ok.body.image_webp, upTo: Self.assetByteLimit)
    case .undocumented: throw URLError(.badServerResponse)
    }
  }

  func modelTile(
    model: String, key: String, variable: String, z: Int, x: Int, y: Int,
    profile: ServerProfile = .standard
  ) async throws -> Data {
    let output = try await client(for: profile).getModelTile(
      .init(path: .init(model: model, key: key, variable: variable, z: z, x: x, y: y)))
    switch output {
    case .ok(let ok):
      return try await Data(collecting: ok.body.image_webp, upTo: Self.assetByteLimit)
    case .undocumented: throw URLError(.badServerResponse)
    }
  }

  func colormap(id: String, profile: ServerProfile = .standard) async throws -> Data {
    switch try await client(for: profile).getColormap(.init(path: .init(id: id))) {
    case .ok(let ok):
      return try await Data(collecting: ok.body.binary, upTo: Self.assetByteLimit)
    case .undocumented: throw URLError(.badServerResponse)
    }
  }

  // MARK: Wind field / storm cells

  func windField(
    model: String, key: String, z: Int, x: Int, y: Int, samples: Int
  ) async throws -> Components.Schemas.WindFieldTile {
    let output = try await oscarServer.getWindField(
      .init(path: .init(model: model, key: key, z: z, x: x, y: y), query: .init(samples: samples)))
    switch output {
    case .ok(let ok): return try ok.body.json
    case .undocumented: throw URLError(.badServerResponse)
    }
  }

  func stormCells(region: String, profile: ServerProfile = .standard) async throws
    -> Components.Schemas.StormCellCollection
  {
    switch try await client(for: profile).getRadarCells(.init(path: .init(region: region))) {
    case .ok(let ok): return try ok.body.json
    case .undocumented: throw URLError(.badServerResponse)
    }
  }
}

struct OscarServerDateTranscoder: DateTranscoder {
  func encode(_ date: Date) throws -> String { PrecipSeriesDate.string(from: date) }

  func decode(_ string: String) throws -> Date {
    guard let date = PrecipSeriesDate.parse(string) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "Unparseable oscar-server date: \(string)"))
    }
    return date
  }
}
