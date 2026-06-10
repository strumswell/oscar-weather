import CoreLocation
import Foundation

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
    let radar: Components.Schemas.RadarResponse
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
