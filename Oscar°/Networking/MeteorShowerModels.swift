import Foundation

/// Location-aware response from Oscar Astro's active meteor-shower endpoint.
/// Context is absent only for the documented unsupported response.
struct MeteorShowerResponse: Codable, Equatable, Sendable {
  let supported: Bool
  let location: MeteorShowerLocation?
  let localDate: String?
  let night: MeteorShowerNight?
  let events: [MeteorShowerEvent]

  init(
    supported: Bool,
    location: MeteorShowerLocation? = nil,
    localDate: String? = nil,
    night: MeteorShowerNight? = nil,
    events: [MeteorShowerEvent]
  ) {
    self.supported = supported
    self.location = location
    self.localDate = localDate
    self.night = night
    self.events = events
  }

  static func decode(from data: Data) throws -> MeteorShowerResponse {
    let response = try MeteorShowerJSON.decoder().decode(MeteorShowerResponse.self, from: data)
    guard !response.supported || (
      response.location != nil && response.localDate != nil && response.night != nil
    ) else {
      throw DecodingError.dataCorrupted(.init(
        codingPath: [],
        debugDescription: "Supported meteor response is missing observing context"
      ))
    }
    return response
  }
}

struct MeteorShowerLocation: Codable, Equatable, Sendable {
  let latitude: Double
  let longitude: Double
  let countryCode: String
  let timezone: String
}

struct MeteorShowerNight: Codable, Equatable, Sendable {
  let sunset: Date?
  let sunrise: Date?
  let darknessStart: Date?
  let darknessEnd: Date?
  let darknessType: String
  let darknessDurationHours: Double
}

struct MeteorShowerEvent: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let name: String
  let status: String
  let presentation: String
  let zhr: Int
  let peak: Date
  let peakEnd: Date?
  let peakPrecision: String
  let visibility: MeteorShowerVisibility
  let radiant: MeteorShowerRadiant
  let source: String

  init(
    id: String,
    name: String,
    status: String = "active",
    presentation: String = "active",
    zhr: Int = 0,
    peak: Date = .distantPast,
    peakEnd: Date? = nil,
    peakPrecision: String = "date",
    visibility: MeteorShowerVisibility = .init(),
    radiant: MeteorShowerRadiant = .init(),
    source: String = "IMO"
  ) {
    self.id = id
    self.name = name
    self.status = status
    self.presentation = presentation
    self.zhr = zhr
    self.peak = peak
    self.peakEnd = peakEnd
    self.peakPrecision = peakPrecision
    self.visibility = visibility
    self.radiant = radiant
    self.source = source
  }
}

struct MeteorShowerVisibility: Codable, Equatable, Sendable {
  let classification: String
  let observable: Bool
  let radiantRises: Bool
  let radiantVisible: Bool
  let maxRadiantAltitude: Double
  let bestTime: Date?

  init(
    classification: String = "fair",
    observable: Bool = true,
    radiantRises: Bool = true,
    radiantVisible: Bool = true,
    maxRadiantAltitude: Double = 0,
    bestTime: Date? = nil
  ) {
    self.classification = classification
    self.observable = observable
    self.radiantRises = radiantRises
    self.radiantVisible = radiantVisible
    self.maxRadiantAltitude = maxRadiantAltitude
    self.bestTime = bestTime
  }
}

struct MeteorShowerRadiant: Codable, Equatable, Sendable {
  let ra: Double
  let dec: Double

  init(ra: Double = 0, dec: Double = 0) {
    self.ra = ra
    self.dec = dec
  }
}

/// Deterministic banner choice: semantic presentation priority wins, then
/// stronger ideal ZHR, then the stable backend ID for a reproducible tie-break.
enum MeteorShowerEventSelector {
  static func select(from events: [MeteorShowerEvent]) -> MeteorShowerEvent? {
    events.min { lhs, rhs in
      let lhsRank = presentationRank(lhs.presentation)
      let rhsRank = presentationRank(rhs.presentation)
      if lhsRank != rhsRank { return lhsRank > rhsRank }
      if lhs.zhr != rhs.zhr { return lhs.zhr > rhs.zhr }
      if lhs.id != rhs.id { return lhs.id < rhs.id }
      return lhs.name < rhs.name
    }
  }

  static func presentationRank(_ presentation: String?) -> Int {
    switch presentation?.lowercased() {
    case "many_tonight": 4
    case "peak_tonight": 3
    case "near_peak": 2
    case "active": 1
    default: 0
    }
  }
}

private enum MeteorShowerJSON {
  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
      let plain = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
      if let date = try? fractional.parse(value) { return date }
      if let date = try? plain.parse(value) { return date }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid ISO-8601 date: \(value)"
      )
    }
    return decoder
  }
}
