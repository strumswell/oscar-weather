import CoreLocation
import Foundation

struct WeatherSnapshot: Codable {
    let forecast: Operations.getForecast.Output.Ok.Body.jsonPayload
    let air: Operations.getAirQuality.Output.Ok.Body.jsonPayload
    let precipSeries: PrecipSeriesResponse?
    let coordinates: CodableCoordinate
    let locationName: String
    let savedAt: Date
}

enum WeatherSnapshotStore {
    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
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

    private static let maxSnapshotDistance: CLLocationDistance = 50_000

    static func coordinatesMatch(
        snapshot: CodableCoordinate,
        current: CLLocationCoordinate2D
    ) -> Bool {
        CLLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
            .distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude))
            < maxSnapshotDistance
    }
}
