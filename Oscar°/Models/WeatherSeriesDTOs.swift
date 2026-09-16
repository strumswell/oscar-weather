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
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
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

// MARK: - Satellite cloud series (oscar-server `/clouds/meteosat/series`)

/// Per-location cloudiness timeline from the satellite layer: IR opacity index
/// 0…255 (brightness-derived cloud presence/thickness, NOT a calibrated cloud
/// fraction — warm low stratus at night reads low), observed 5-min series plus
/// the per-point nowcast. Not persisted: the trend is only meaningful fresh.
struct CloudSeriesResponse: Codable, Equatable {
    let source: String
    let latitude: Double
    let longitude: Double
    let series: [CloudPoint]
    let generatedAt: String?
    let forecastHorizon: String?

    enum CodingKeys: String, CodingKey {
        case source, latitude, longitude, series
        case generatedAt = "generated_at"
        case forecastHorizon = "forecast_horizon"
    }
}

struct CloudPoint: Codable, Equatable {
    let timestamp: Date
    let value: Int
    let isForecast: Bool

    enum CodingKeys: String, CodingKey {
        case timestamp, value
        case isForecast = "is_forecast"
    }

    init(timestamp: Date, value: Int, isForecast: Bool) {
        self.timestamp = timestamp
        self.value = value
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
        value = try container.decode(Int.self, forKey: .value)
        isForecast = try container.decodeIfPresent(Bool.self, forKey: .isForecast) ?? false
    }
}

/// A sky transition the satellite nowcast is confident about: the head view's
/// cloud metric annotates itself with the direction and minute.
struct CloudTrend: Equatable {
    enum Direction {
        case clearing
        case clouding
    }

    let direction: Direction
    let at: Date
}

extension CloudSeriesResponse {
    /// Opacity index at/above which the sky counts as overcast…
    private static let cloudyOn = 100
    /// …and below which it counts as clear. The band between is indeterminate:
    /// it never triggers a transition on its own (hysteresis against thin
    /// cirrus flapping the arrow).
    private static let clearOff = 60
    /// Consecutive future samples (5-min) the new state must hold — a
    /// transition that immediately reverts is noise, not weather.
    private static let dwellSamples = 3
    /// Only announce transitions inside this window.
    private static let horizon: TimeInterval = 100 * 60

    /// The first well-supported clear↔cloudy flip after `now`, or nil when the
    /// sky just stays whatever it is (the common case, and the quiet default).
    func trend(now: Date = .now) -> CloudTrend? {
        let sorted = series.sorted { $0.timestamp < $1.timestamp }
        let past = sorted.filter { $0.timestamp <= now }
        let future = sorted.filter { $0.timestamp > now && $0.timestamp <= now.addingTimeInterval(Self.horizon) }
        guard !future.isEmpty else { return nil }

        // Current state: the newest determinate past sample (mid-band readings
        // keep looking further back; an all-indeterminate past yields no trend).
        guard let current = past.reversed().lazy.compactMap(Self.classify).first else { return nil }

        for (index, point) in future.enumerated() {
            guard let state = Self.classify(point), state != current else { continue }
            // The flip plus its dwell window must stay out of the ORIGINAL
            // state — the indeterminate band may participate in the new one.
            let window = future[index..<min(index + Self.dwellSamples, future.count)]
            guard window.count == Self.dwellSamples else { return nil }   // horizon cut
            let holds = window.allSatisfy { sample in
                current == .cloudy ? sample.value < Self.cloudyOn : sample.value >= Self.clearOff
            }
            guard holds else { continue }
            return CloudTrend(
                direction: current == .cloudy ? .clearing : .clouding,
                at: point.timestamp)
        }
        return nil
    }

    private enum SkyState { case clear, cloudy }

    private static func classify(_ point: CloudPoint) -> SkyState? {
        if point.value >= cloudyOn { return .cloudy }
        if point.value < clearOff { return .clear }
        return nil
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
