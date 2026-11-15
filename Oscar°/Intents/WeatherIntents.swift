// Siri and Shortcuts intents that answer rain and weather questions without opening the app.
import AppIntents
import CoreLocation
import SwiftUI
import WidgetKit

struct RainNowcastIntent: AppIntent {
    static let title: LocalizedStringResource = "Regnet es bald?"
    static let description = IntentDescription("Sagt dir, ob in den nächsten 90 Minuten Regen kommt.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Ort", optionsProvider: WidgetCityOptionsProvider())
    var city: String?

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let place = await widgetPlace(for: city)
        let name = await place.locationName()
        async let forecast = place.isFixed ? try? siriForecast(place.coordinates) : nil
        guard let series = try await APIClient.shared.getRadarSeries(coordinates: place.coordinates) else {
            return .result(dialog: "Für \(name) gibt es keine Radardaten.", view: EmptyView())
        }
        let timeZone = await forecast?.locationTimeZone ?? .current
        let now = Date()
        let points = RainNowcastSummary.points(from: series, now: now)
        let headline = RainNowcastSummary.headline(for: points, now: now, timeZone: timeZone)
        var spoken = "\(name): \(RainNowcastSummary.spokenHeadline(for: points, now: now, timeZone: timeZone))"
        if let peak = RainNowcastSummary.peak(in: points) {
            let rate = "\(RainIntensity.format(peak.precipitation)) \(RainIntensity.unit)"
            spoken += " " + String(localized: "Am stärksten um \(SettingService.formattedTime(peak.timestamp, timeZone: timeZone)) mit \(rate).")
        }
        return .result(
            dialog: IntentDialog(stringLiteral: spoken),
            view: RainNowcastSnippet(headline: headline, values: RainNowcastSummary.values(points))
        )
    }
}

struct CurrentWeatherIntent: AppIntent {
    static let title: LocalizedStringResource = "Wie ist das Wetter?"
    static let description = IntentDescription("Sagt dir Temperatur, Wetterlage und die Werte für heute.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Ort", optionsProvider: WidgetCityOptionsProvider())
    var city: String?

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let place = await widgetPlace(for: city)
        let name = await place.locationName()
        async let radar = try? APIClient.shared.getRadarSeries(coordinates: place.coordinates)
        let weather = try await siriForecast(place.coordinates)
        guard let current = weather.current,
              let high = weather.daily?.temperature_2m_max?.first,
              let low = weather.daily?.temperature_2m_min?.first else {
            return .result(dialog: "Für \(name) gibt es gerade keine Wetterdaten.", view: EmptyView())
        }
        let radarRate = await radar?.rate(at: Date())
        let code = WeatherConditionLabel.code(weathercode: current.weathercode, radarRate: radarRate)
        let units = SettingService.resolvedUnits
        let snippet = CurrentWeatherSnippet(
            place: name,
            temperature: units.temperatureString(current.temperature),
            condition: WeatherConditionLabel.text(for: code),
            high: units.temperatureString(high),
            low: units.temperatureString(low),
            symbol: WeatherSymbol.sfSymbol(
                weathercode: Double(code),
                isDay: current.is_day ?? 1,
                isRaining: code >= 51,
                precipitation: radarRate ?? 0
            )
        )
        let spoken = String(localized: "\(snippet.place): \(snippet.condition), \(snippet.temperature). Heute \(snippet.low) bis \(snippet.high).")
        return .result(dialog: IntentDialog(stringLiteral: spoken), view: snippet)
    }
}

private func siriForecast(_ coordinates: CLLocationCoordinate2D) async throws -> Operations.getForecast.Output.Ok.Body.jsonPayload {
    try await APIClient.shared.getForecast(coordinates: coordinates, forecastDays: ._1, hourly: [.precipitation_probability])
}

struct OscarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RainNowcastIntent(),
            phrases: [
                "Regnet es bald in \(.applicationName)",
                "Regnet es bald laut \(.applicationName)",
                "Kommt Regen in \(.applicationName)",
            ],
            shortTitle: "Regnet es bald?",
            systemImageName: "cloud.rain"
        )
        AppShortcut(
            intent: CurrentWeatherIntent(),
            phrases: [
                "Wetter in \(.applicationName)",
                "Wie ist das Wetter in \(.applicationName)",
            ],
            shortTitle: "Wetter jetzt",
            systemImageName: "thermometer.medium"
        )
        AppShortcut(
            intent: OpenRadarIntent(),
            phrases: [
                "Regenradar in \(.applicationName)",
                "Öffne das Regenradar in \(.applicationName)",
            ],
            shortTitle: "Regenradar",
            systemImageName: "map"
        )
    }
}

private struct RainNowcastSnippet: View {
    let headline: String
    let values: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headline)
                .font(.headline)
            RainBarsChart(values: values, height: 44)
        }
        .padding()
        .environment(\.widgetRenderingMode, .accented)
    }
}

private struct CurrentWeatherSnippet: View {
    let place: String
    let temperature: String
    let condition: String
    let high: String
    let low: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.largeTitle)
            VStack(alignment: .leading, spacing: 2) {
                Text(place)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(temperature)
                    .font(.largeTitle.weight(.semibold))
                HStack(spacing: 6) {
                    Text(condition)
                    Text("H: \(high)", comment: "Höchste Temperatur")
                    Text("T: \(low)", comment: "Niedrigste Temperatur")
                }
                .font(.footnote)
            }
            Spacer(minLength: 0)
        }
        .monospacedDigit()
        .padding()
    }
}
