import Foundation

/// Meteor observing conditions from oscar-server's `GET /astro/meteors`.
/// The server plans the night containing the request time, or the next night,
/// and rates it from geometry, moonlight, ECMWF cloud cover and radar nowcasts.
/// All timestamps are UTC instants; the app labels them in the forecast's zone.
struct MeteorShowerResponse: Codable, Equatable, Sendable {
  /// good | fair | poor | unknown | unobservable
  let condition: String
  /// The best span across all active showers; nil when nothing is observable.
  let bestWindow: MeteorShowerWindow?
  let night: MeteorShowerNight
  /// Streams whose activity season covers the night, each rated on its own.
  let showers: [MeteorShowerEvent]
  /// Provenance of the weather behind `bestWindow`.
  let weather: MeteorShowerWeatherSource
  let validUntil: Date
  /// Present only when the condition is limited, e.g. `cloud_cover`, `low_activity`.
  let reasons: [String]?

  init(
    condition: String,
    bestWindow: MeteorShowerWindow? = nil,
    night: MeteorShowerNight = .init(),
    showers: [MeteorShowerEvent] = [],
    weather: MeteorShowerWeatherSource = .init(),
    validUntil: Date,
    reasons: [String]? = nil
  ) {
    self.condition = condition
    self.bestWindow = bestWindow
    self.night = night
    self.showers = showers
    self.weather = weather
    self.validUntil = validUntil
    self.reasons = reasons
  }

  /// The shower the server ranked best tonight, if it is among `showers`.
  var primaryShower: MeteorShowerEvent? {
    guard let id = bestWindow?.shower else { return nil }
    return showers.first { $0.id == id }
  }

  static func decode(from data: Data) throws -> MeteorShowerResponse {
    try MeteorShowerJSON.decoder().decode(MeteorShowerResponse.self, from: data)
  }
}

/// Contiguous 30-minute slots sharing the best condition.
struct MeteorShowerWindow: Codable, Equatable, Sendable {
  let start: Date
  let end: Date
  /// Catalogue ID of the shower this window belongs to, e.g. `PER`.
  let shower: String
  /// Highest radiant altitude across the span, in degrees.
  let radiantAltitude: Double
  /// Illuminated fraction 0…1, independent of whether the moon is up.
  let moonIllumination: Double
  /// Worst cloud cover across the span in percent; nil without weather coverage.
  let cloudCover: Double?
  /// Worst radar rain rate across the span; nil without radar coverage.
  let precipitationMmH: Double?

  init(
    start: Date,
    end: Date,
    shower: String,
    radiantAltitude: Double = 0,
    moonIllumination: Double = 0,
    cloudCover: Double? = nil,
    precipitationMmH: Double? = nil
  ) {
    self.start = start
    self.end = end
    self.shower = shower
    self.radiantAltitude = radiantAltitude
    self.moonIllumination = moonIllumination
    self.cloudCover = cloudCover
    self.precipitationMmH = precipitationMmH
  }
}

struct MeteorShowerNight: Codable, Equatable, Sendable {
  let darknessStart: Date?
  let darknessEnd: Date?
  /// Deepest twilight reached for at least 30 minutes:
  /// astronomical | nautical | civil | sun_below_horizon | none
  let type: String

  init(darknessStart: Date? = nil, darknessEnd: Date? = nil, type: String = "none") {
    self.darknessStart = darknessStart
    self.darknessEnd = darknessEnd
    self.type = type
  }
}

struct MeteorShowerEvent: Codable, Equatable, Sendable, Identifiable {
  /// Stable catalogue ID (`QUA`, `LYR`, `ETA`, `SDA`, `PER`, `ORI`, `LEO`, `GEM`, `URS`).
  let id: String
  let peak: Date
  /// 3 for a reviewed IMO peak, at least 24 for an annual estimate.
  let uncertaintyHours: Double
  let condition: String
  let bestWindow: MeteorShowerWindow?

  init(
    id: String,
    peak: Date = .distantPast,
    uncertaintyHours: Double = 3,
    condition: String = "fair",
    bestWindow: MeteorShowerWindow? = nil
  ) {
    self.id = id
    self.peak = peak
    self.uncertaintyHours = uncertaintyHours
    self.condition = condition
    self.bestWindow = bestWindow
  }

  /// Annual solar-longitude estimates can miss the real peak by a day or more.
  var isPeakEstimated: Bool { uncertaintyHours >= 24 }
}

struct MeteorShowerWeatherSource: Codable, Equatable, Sendable {
  /// ecmwf | meteosat-nowcast | none
  let source: String
  let issuedAt: Date?
  /// dwd-nowcast | opera-nowcast | mrms-nowcast | cwa-nowcast | redemet-nowcast | aemet-nowcast
  let precipitationSource: String?

  init(source: String = "none", issuedAt: Date? = nil, precipitationSource: String? = nil) {
    self.source = source
    self.issuedAt = issuedAt
    self.precipitationSource = precipitationSource
  }
}

/// Client-side facts about the nine streams the server rates. The server's
/// `Sources/App/Resources/meteor_showers.json` is the source of truth; the
/// response carries only IDs, so the ideal hourly rate lives here.
enum MeteorShowerCatalogue {
  static let typicalZHR: [String: Int] = [
    "QUA": 80,
    "LYR": 18,
    "ETA": 50,
    "SDA": 25,
    "PER": 100,
    "ORI": 20,
    "LEO": 15,
    "GEM": 150,
    "URS": 10,
  ]
}

private enum MeteorShowerJSON {
  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      let plain = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
      let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
      if let date = try? plain.parse(value) { return date }
      if let date = try? fractional.parse(value) { return date }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid ISO-8601 date: \(value)"
      )
    }
    return decoder
  }
}
