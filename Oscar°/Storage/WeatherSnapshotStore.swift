import CoreLocation
import Foundation

// MARK: - Radar precipitation series (oscar-server `/radar/series`)

/// Per-location precipitation timeline in mm/h returned by oscar-server's
/// `/radar/series` endpoint. Auto-routes DWD inside Germany / OPERA elsewhere
/// in Europe and includes both observations and nowcast frames.
///
/// `Codable` because it is persisted in `WeatherSnapshot`. Timestamps are kept
/// as raw ISO8601 strings where they are not consumed by the UI; per-point
/// timestamps decode to `Date` via `PrecipPoint`'s explicit Codable so the
/// snapshot round-trips under a plain `JSONDecoder`/`JSONEncoder`.
struct PrecipSeriesResponse: Codable, Equatable {
    let source: String
    let unit: String
    let latitude: Double
    let longitude: Double
    let series: [PrecipPoint]
    let generatedAt: String?
    let lastObservedAt: String?
    let forecastHorizon: String?

    enum CodingKeys: String, CodingKey {
        case source, unit, latitude, longitude, series
        case generatedAt = "generated_at"
        case lastObservedAt = "last_observed_at"
        case forecastHorizon = "forecast_horizon"
    }
}

struct PrecipPoint: Codable, Equatable {
    let timestamp: Date
    let precipitation: Double  // mm/h
    let isForecast: Bool

    enum CodingKeys: String, CodingKey {
        case timestamp, precipitation
        case isForecast = "is_forecast"
    }

    init(timestamp: Date, precipitation: Double, isForecast: Bool) {
        self.timestamp = timestamp
        self.precipitation = precipitation
        self.isForecast = isForecast
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .timestamp)
        guard let date = PrecipSeriesDate.parse(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp, in: container,
                debugDescription: "Unparseable timestamp: \(raw)"
            )
        }
        timestamp = date
        precipitation = try container.decode(Double.self, forKey: .precipitation)
        isForecast = try container.decodeIfPresent(Bool.self, forKey: .isForecast) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(PrecipSeriesDate.string(from: timestamp), forKey: .timestamp)
        try container.encode(precipitation, forKey: .precipitation)
        try container.encode(isForecast, forKey: .isForecast)
    }
}

/// ISO8601 parsing/formatting shared by `PrecipPoint` (server emits millisecond
/// fractional seconds, e.g. `2026-06-17T12:05:00.000Z`).
enum PrecipSeriesDate {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ string: String) -> Date? {
        fractional.date(from: string)
            ?? plain.date(from: string)
            ?? Double(string).map { Date(timeIntervalSince1970: $0) }
    }

    static func string(from date: Date) -> String {
        fractional.string(from: date)
    }
}

struct CodableCoordinate: Codable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct WeatherSnapshot: Codable {
    let forecast: Operations.getForecast.Output.Ok.Body.jsonPayload
    let air: Operations.getAirQuality.Output.Ok.Body.jsonPayload
    // Optional so snapshots written by older builds (which stored a BrightSky
    // `radar` field instead) decode gracefully as "no series" rather than throwing.
    let precipSeries: PrecipSeriesResponse?
    let coordinates: CodableCoordinate
    let locationName: String
    let savedAt: Date
}

enum WeatherSnapshotStore {
    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.cloud.bolte.Oscar")?
            .appendingPathComponent("lastWeatherSnapshot.json")
    }

    static func save(_ snapshot: WeatherSnapshot) {
        guard let url, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load(maxAge: TimeInterval = 6 * 3_600) -> WeatherSnapshot? {
        guard let url,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: data),
              Date().timeIntervalSince(snapshot.savedAt) < maxAge else {
            return nil
        }
        return snapshot
    }
}
