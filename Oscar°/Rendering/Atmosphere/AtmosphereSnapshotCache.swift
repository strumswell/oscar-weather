import CoreLocation

/// Memoizes `AtmosphereWeatherMapper.snapshot` across body re-evaluations; recomputes
/// only when the weather data (`lastUpdated`), location, or a coarse 60-second
/// time bucket changes. Held via `@State` and only touched on the main actor.
@MainActor
final class AtmosphereSnapshotCache {
    private struct Key: Equatable {
        let lastUpdated: Date?
        let latitude: Double
        let longitude: Double
        let timeBucket: Int
    }

    private var key: Key?
    private var cached: AtmosphereSnapshot?

    func snapshot(from weather: Weather, at location: CLLocationCoordinate2D) -> AtmosphereSnapshot {
        let key = Key(
            lastUpdated: weather.lastUpdated,
            latitude: location.latitude,
            longitude: location.longitude,
            timeBucket: Int(Date.now.timeIntervalSince1970 / 60)
        )
        if key == self.key, let cached {
            return cached
        }

        let snapshot = AtmosphereWeatherMapper.snapshot(from: weather, at: location)
        self.key = key
        self.cached = snapshot
        return snapshot
    }
}
