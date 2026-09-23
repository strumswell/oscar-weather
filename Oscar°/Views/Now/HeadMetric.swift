import SwiftUI

/// The readings under the big temperature (`SettingService.headMetrics`).
/// Current-conditions values come straight from `current`; the rest sample
/// the hourly series at the present hour.
enum HeadMetric: String, CaseIterable, Identifiable {
    case cloudCover, wind, windDirection, feelsLike, humidity, uvIndex, pressure, precipitationChance, gusts, measured

    static let maxShown = 4
    /// Out of the box only cloud cover, wind and wind direction are shown.
    static let defaultHidden: Set<HeadMetric> = [.feelsLike, .humidity, .uvIndex, .pressure, .precipitationChance, .gusts, .measured]

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .cloudCover: "Bewölkung"
        case .wind: "Wind"
        case .windDirection: "Windrichtung"
        case .feelsLike: "Gefühlt"
        case .humidity: "Luftfeuchtigkeit"
        case .uvIndex: "UV-Index"
        case .pressure: "Luftdruck"
        case .precipitationChance: "Regenwahrscheinlichkeit"
        case .gusts: "Böen"
        case .measured: "Gemessen"
        }
    }

    var systemImage: String {
        switch self {
        case .cloudCover: "cloud"
        case .wind: "wind"
        case .windDirection: "location"
        case .feelsLike: "thermometer.medium"
        case .humidity: "humidity"
        case .uvIndex: "sun.max"
        case .pressure: "barometer"
        case .precipitationChance: "umbrella"
        case .gusts: "wind.snow"
        case .measured: "sensor"
        }
    }

    /// Settings tile color; a fixed hue per reading so rows read at a glance.
    var tint: Color {
        switch self {
        case .cloudCover: .gray
        case .wind: .teal
        case .windDirection: .cyan
        case .feelsLike: .orange
        case .humidity: .mint
        case .uvIndex: .purple
        case .pressure: .indigo
        case .precipitationChance: .blue
        case .gusts: .green
        case .measured: .brown
        }
    }

    /// Formatted value, nil when the data isn't there (the row skips it).
    @MainActor
    func value(in weather: Weather) -> String? {
        let current = weather.forecast.current
        let hourly = weather.forecast.hourly
        let time = hourly?.time ?? []
        switch self {
        case .cloudCover:
            return current.map { "\(Int($0.cloudcover.rounded())) %" }
        case .wind:
            return current.map { Self.windString($0.windspeed, weather: weather) }
        case .windDirection:
            return current?.getWindDirection()
        case .feelsLike:
            return environmentValue(from: hourly?.apparent_temperature, time: time)
                .map { HourlyFormatting.temperatureString($0) }
        case .humidity:
            return environmentValue(from: hourly?.relativehumidity_2m, time: time)
                .map { "\(Int($0.rounded())) %" }
        case .uvIndex:
            return environmentValue(from: weather.air.hourly?.uv_index, time: weather.air.hourly?.time ?? [])
                .map { "UV \(Int($0.rounded()))" }
        case .pressure:
            return environmentValue(from: hourly?.pressure_msl, time: time)
                .map { "\(Int($0.rounded())) hPa" }
        case .precipitationChance:
            return (environmentValue(from: hourly?.precipitation_probability, time: time) ?? nil)
                .map { "\(Int($0.rounded())) %" }
        case .gusts:
            return environmentValue(from: hourly?.windgusts_10m, time: time)
                .map { Self.windString($0, weather: weather) }
        case .measured:
            // The nearest station's reading, next to (never instead of) the forecast temperature.
            return weather.stations.first?.current.temperature.map { StationUnits().temperatureString($0) }
        }
    }

    /// Speeds arrive in the chosen unit; Beaufort is derived on device from km/h.
    @MainActor
    private static func windString(_ speed: Double, weather: Weather) -> String {
        let unit = WindSpeedUnit(settingValue: SettingService.shared.windSpeedUnit)
        if unit.usesBeaufortDisplay {
            return WindSpeedFormatter.string(BeaufortScale.value(forKilometersPerHour: speed), unit: unit.displayUnit)
        }
        return WindSpeedFormatter.string(speed, unit: weather.forecast.hourly_units?.windspeed_10m ?? "km/h")
    }
}

extension SettingService {
    /// Every reading in the user's order. Readings missing from the stored
    /// order (new ones) fall in at the end.
    var headMetricOrder: [HeadMetric] {
        get {
            let stored = (headMetricOrderRaw ?? []).compactMap(HeadMetric.init(rawValue:))
            return stored + HeadMetric.allCases.filter { !stored.contains($0) }
        }
        set { headMetricOrderRaw = newValue.map(\.rawValue) }
    }

    var hiddenHeadMetrics: Set<HeadMetric> {
        get { hiddenHeadMetricsRaw.map { Set($0.compactMap(HeadMetric.init(rawValue:))) } ?? HeadMetric.defaultHidden }
        set { hiddenHeadMetricsRaw = newValue.map(\.rawValue).sorted() }
    }

    /// The readings under the big temperature, in order.
    var headMetrics: [HeadMetric] {
        headMetricOrder.filter { !hiddenHeadMetrics.contains($0) }
    }
}
