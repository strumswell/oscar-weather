// The shared forecast and radar requests behind every widget and control, cached per place.
import CoreLocation
import Foundation

enum WidgetForecast {
    typealias Payload = Operations.getForecast.Output.Ok.Body.jsonPayload

    private static let hourly: [Operations.getForecast.Input.Query.hourlyPayloadPayload] = [
        .temperature_2m, .weathercode, .is_day, .cloudcover, .relativehumidity_2m, .precipitation,
        .precipitation_probability, .snowfall, .windspeed_10m, .winddirection_10m, .windgusts_10m,
    ]

    static func forecast(_ coordinates: CLLocationCoordinate2D) async throws -> (value: Payload, fetchedAt: Date) {
        try await WidgetCache.fetch(WidgetCache.key("forecast", coordinates), maxAge: 600) {
            try await APIClient.shared.getForecast(coordinates: coordinates, forecastDays: ._7, hourly: hourly)
        }
    }

    static func daily(_ coordinates: CLLocationCoordinate2D) async throws -> (value: Payload, fetchedAt: Date) {
        try await WidgetCache.fetch(WidgetCache.key("daily", coordinates), maxAge: 600) {
            try await APIClient.shared.getForecast(coordinates: coordinates, forecastDays: ._14, hourly: hourly)
        }
    }

    static func radar(_ coordinates: CLLocationCoordinate2D) async throws -> PrecipSeriesResponse? {
        try await WidgetCache.fetch(WidgetCache.key("radar", coordinates), maxAge: 120, maxStale: 20 * 60) {
            try await APIClient.shared.getRadarSeries(coordinates: coordinates)
        }.value
    }

    static func cachedTimeZone(_ coordinates: CLLocationCoordinate2D) -> TimeZone {
        let cached: Payload? = WidgetCache.cached(WidgetCache.key("forecast", coordinates))
        return cached?.locationTimeZone ?? .current
    }
}

extension Operations.getForecast.Output.Ok.Body.jsonPayload {
    func hourIndex(at date: Date) -> Int? {
        let hours = hourly?.time ?? []
        let time = date.timeIntervalSince1970
        return hours.indices.min { abs(time - hours[$0]) < abs(time - hours[$1]) }
    }

    func dayIndex(at date: Date) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = locationTimeZone
        return daily?.time.firstIndex { calendar.isDate(Date(timeIntervalSince1970: $0), inSameDayAs: date) }
    }
}

extension Array {
    subscript(safe index: Int?) -> Element? {
        guard let index, indices.contains(index) else { return nil }
        return self[index]
    }
}
