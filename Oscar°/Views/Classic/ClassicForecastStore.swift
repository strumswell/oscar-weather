//
//  ClassicForecastStore.swift
//  Oscar°
//
//  Forecasts for every place the classic (iOS 6) theme pages through. The
//  modern app keeps one live `Weather` for the selected place; the classic
//  deck shows all places at once, so it fetches one forecast per place
//  through the same generated client (units, model preference and URL cache
//  come along for free).
//

import CoreLocation
import Foundation
import Observation

struct ClassicPlace: Identifiable, Hashable {
    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
    let isCurrentLocation: Bool

    static func == (lhs: ClassicPlace, rhs: ClassicPlace) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ClassicForecast {
    typealias Payload = Operations.getForecast.Output.Ok.Body.jsonPayload

    let payload: Payload
    /// The sky the location cards render for this place; the classic card
    /// paints its gradient from it. Radar-aware like the main sim.
    let sky: AtmosphereSnapshot
    /// Fresh radar measured rain right now.
    let isRadarRaining: Bool

    /// The code the "now" art follows: measured rain over a dry forecast
    /// code reads as rain, same rule as the map chips and widgets.
    var currentWeatherCode: Double {
        let code = payload.current?.weathercode ?? 0
        let isPrecipitation = [51...57, 61...67, 71...77, 80...86, 95...99].contains { $0.contains(Int(code)) }
        return isRadarRaining && !isPrecipitation ? 61 : code
    }
}

@MainActor
@Observable
final class ClassicForecastStore {
    static let shared = ClassicForecastStore()

    private(set) var places: [ClassicPlace] = []
    private(set) var forecasts: [ClassicPlace.ID: ClassicForecast] = [:]
    private(set) var updatedAt: Date?

    private init() {}

    /// Rebuilds the page list (GPS spot first, then the saved cities in the
    /// user's order) and fetches every forecast, or with `onlyMissing` just
    /// the places without one. A failed fetch keeps the previous forecast
    /// for that place.
    func refresh(onlyMissing: Bool = false) async {
        var next: [ClassicPlace] = []
        if let gps = LocationService.shared.getGPSCoordinates() {
            next.append(ClassicPlace(
                id: "current-location",
                title: CityService.shared.currentLocationDisplayName,
                coordinate: gps,
                isCurrentLocation: true
            ))
        }
        for city in CityService.shared.cities {
            next.append(ClassicPlace(
                id: city.objectID.uriRepresentation().absoluteString,
                title: city.displayName,
                coordinate: CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon),
                isCurrentLocation: false
            ))
        }
        places = next

        // Payloads and radar are fetched off the main actor; the sky snapshots
        // need it (the mapper reads a `Weather` shell), so they are built
        // afterwards. Radar is best effort: no coverage is simply no radar.
        let payloads = await withTaskGroup(of: (ClassicPlace.ID, Payload?, PrecipSeriesResponse?).self) { group in
            for place in next where !onlyMissing || forecasts[place.id] == nil {
                group.addTask {
                    async let radar = try? APIClient.shared.getRadarSeries(coordinates: place.coordinate)
                    let payload = try? await APIClient.shared.getForecast(coordinates: place.coordinate)
                    return (place.id, payload, await radar)
                }
            }
            var result: [ClassicPlace.ID: (Payload, PrecipSeriesResponse?)] = [:]
            for await (id, payload, radar) in group {
                if let payload { result[id] = (payload, radar) }
            }
            return result
        }
        var fetched: [ClassicPlace.ID: ClassicForecast] = [:]
        for place in next {
            guard let (payload, radar) = payloads[place.id] else { continue }
            fetched[place.id] = ClassicForecast(
                payload: payload,
                sky: Self.sky(for: payload, radar: radar, at: place.coordinate),
                isRadarRaining: radar?.isRaining() ?? false
            )
        }

        forecasts = forecasts.filter { entry in next.contains { $0.id == entry.key } }
        forecasts.merge(fetched) { _, new in new }
        if !fetched.isEmpty { updatedAt = .now }
    }

    private typealias Payload = ClassicForecast.Payload

    private static func sky(
        for payload: Payload,
        radar: PrecipSeriesResponse?,
        at coordinate: CLLocationCoordinate2D
    ) -> AtmosphereSnapshot {
        let shell = Weather()
        shell.forecast = payload
        // The mapper lifts a dry forecast to a rainy scene when the radar
        // measures rain, same as the main sim.
        shell.precipSeries = radar
        return AtmosphereWeatherMapper.snapshot(from: shell, at: coordinate)
    }
}
