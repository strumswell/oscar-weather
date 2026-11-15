// Nearby station observations for the station widgets.
import CoreLocation
import SwiftUI
import WidgetKit

struct StationsEntry: TimelineEntry {
    let date: Date
    let stations: [Components.Schemas.NearbyStation]
    let head: Components.Schemas.NearbyStation?
    let isDay: Bool
    var cityID: String? = nil
    var timeZone: TimeZone = .current
}

struct StationsProvider: PlaceTimelineSource {
    let refreshMinutes = 15

    func placeholder(in context: Context) -> StationsEntry {
        .sample
    }

    func entries(for place: WidgetPlace, family: WidgetFamily) async throws -> [StationsEntry] {
        let coordinates = place.coordinates
        let (stations, _) = try await WidgetCache.fetch(WidgetCache.key("stations", coordinates), maxAge: 120) {
            try await APIClient.shared.getNearbyStations(coordinates: coordinates)
        }
        let favorites = AppGroup.defaults.stringArray(forKey: "favoriteStationIDs") ?? []
        let now = Date()
        return [StationsEntry(
            date: now,
            stations: stations,
            head: stations.head(favorites: favorites),
            isDay: sunIsUp(at: now, coordinates: coordinates),
            cityID: place.cityID,
            timeZone: WidgetForecast.cachedTimeZone(coordinates)
        )]
    }
}

private func sunIsUp(at date: Date, coordinates: CLLocationCoordinate2D) -> Bool {
    let day = Double(Calendar(identifier: .gregorian).ordinality(of: .day, in: .year, for: date) ?? 1)
    let utcHours = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) / 3600
    let hourAngle = (utcHours + coordinates.longitude / 15 - 12) * .pi / 12
    let declination = 0.4095 * sin(0.0172 * day - 1.39)
    let latitude = coordinates.latitude * .pi / 180
    return sin(declination) * sin(latitude) + cos(declination) * cos(latitude) * cos(hourAngle) > 0
}

extension StationsEntry {
    static let sample: StationsEntry = {
        let stations = [
            sampleStation(id: "sample-1", name: "Leipzig-Holzhausen", distance: 7, bearing: 135, base: 5.6, rain: 0.4, code: 3),
            sampleStation(id: "sample-2", name: "Leipzig/Halle", distance: 14, bearing: 315, base: 5.1, rain: 0, code: nil),
            sampleStation(id: "sample-3", name: "Oschatz", distance: 48, bearing: 90, base: 4.4, rain: nil, code: nil),
        ]
        return StationsEntry(date: .now, stations: stations, head: stations.first, isDay: true)
    }()

    static let empty = StationsEntry(date: .now, stations: [], head: nil, isDay: true)

    private static func sampleStation(
        id: String, name: String, distance: Double, bearing: Double, base: Double, rain: Double?, code: Int?
    ) -> Components.Schemas.NearbyStation {
        let now = Date.now
        let history = (0...48).map { step in
            let hours = Double(step) / 2
            return Components.Schemas.StationReading(
                time: now.addingTimeInterval((hours - 24) * 3600),
                temperature_c: base + 3.2 * sin((hours - 9) / 24 * 2 * .pi - 1.2),
                pressure_hpa: 1013.8 - hours * 0.075,
                precipitation_mm: rain == nil ? nil : 0,
                precipitation_period_min: rain == nil ? nil : 30)
        }
        let current = Components.Schemas.StationReading(
            time: now,
            temperature_c: history.last?.temperature_c,
            humidity_pct: 87,
            dew_point_c: 4.8,
            wind_speed_ms: 3.9,
            wind_direction_deg: 225,
            wind_gust_ms: 8.6,
            pressure_hpa: history.last?.pressure_hpa,
            weather_code: code)
        return Components.Schemas.NearbyStation(
            id: id, name: name, source: "esoh", latitude: 51.3, longitude: 12.4,
            distance_km: distance, bearing_deg: bearing, last_report_at: now,
            current: current, precipitation_24h_mm: rain, history: history)
    }
}
