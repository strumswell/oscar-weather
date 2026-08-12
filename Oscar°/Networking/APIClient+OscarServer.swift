import Foundation
import OpenAPIRuntime

// MARK: - oscar-server accessors (generated client)
//
// Every oscar-server endpoint the app consumes goes through the generated
// OpenAPI client via these accessors — JSON endpoints return generated
// schema types, asset endpoints (WebP value grids, tiles, palettes) return
// raw Data. The only oscar-server calls NOT here are the two GeoJSON
// passthroughs (`getWeatherAlertPolygons`, `getPressureIsolines`): MapLibre
// consumes those as raw bytes, and round-tripping megabyte FeatureCollections
// through the generated freeform JSON container would box every coordinate.

extension APIClient {
  /// Upper bound for collected asset bodies (largest today: ~1.5 MB cloud grids).
  private static let assetByteLimit = 64 * 1024 * 1024

  /// Which oscar-server client serves a call: `.standard` retries with backoff
  /// (in-app, a late answer still helps); `.snapshot` caps every request at 20 s
  /// with no retries, for renderers on a WidgetKit refresh budget.
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

  /// nil = clouds not ready yet (404/503) — callers treat it as "no frames",
  /// distinct from transport errors (thrown as-is) and other bad statuses
  /// (thrown as `URLError(.badServerResponse)`).
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

  /// nil = 404, which the radar/model states render as a dry (fully
  /// transparent) frame rather than an error.
  func radarGrid(region: String, key: String, typed: Bool) async throws -> Data? {
    let output = try await oscarServer.getRadarGrid(
      .init(path: .init(region: region, key: key), query: .init(style: typed ? "typed" : nil)))
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

  /// nil = 404, rendered as a dry frame (see `radarGrid`).
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
