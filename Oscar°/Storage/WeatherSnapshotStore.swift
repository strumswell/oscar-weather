import CoreLocation
import Foundation

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

    static func load(maxAge: TimeInterval = 7 * 24 * 3_600) -> WeatherSnapshot? {
        guard let url,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: data),
              Date().timeIntervalSince(snapshot.savedAt) < maxAge else {
            return nil
        }
        return snapshot
    }

    /// How far the cached snapshot may sit from the current location and still
    /// stand in until the first refresh lands. Generous on purpose: forecasts
    /// are area data, and the alternative to hydrating is the twilight
    /// fallback, which is wrong everywhere.
    private static let maxSnapshotDistance: CLLocationDistance = 50_000

    /// Whether the cached snapshot may bridge the launch gap for `current`.
    /// A distance check, NOT coordinate equality: consecutive GPS fixes drift
    /// (the location manager runs at kilometer accuracy), so comparing rounded
    /// coordinates threw the cache away on nearly every cold start in
    /// current-location mode.
    static func coordinatesMatch(
        snapshot: CodableCoordinate,
        current: CLLocationCoordinate2D
    ) -> Bool {
        CLLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
            .distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude))
            < maxSnapshotDistance
    }
}
