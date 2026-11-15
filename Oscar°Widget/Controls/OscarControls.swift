// Control Center controls: radar shortcut and current weather for the app's place.
#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit

struct RadarControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "RadarControl") {
            ControlWidgetButton(action: OpenRadarIntent()) {
                Label("Regenradar", systemImage: "cloud.rain")
            }
        }
        .displayName("Regenradar")
        .description("Öffnet die Karten mit dem Regenradar.")
    }
}

struct WeatherControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "WeatherControl", provider: WeatherControlProvider()) { value in
            ControlWidgetButton(action: OpenWeatherIntent()) {
                Label {
                    Text(value.title)
                    if let subtitle = value.subtitle {
                        Text(subtitle)
                    }
                } icon: {
                    Image(systemName: value.symbol)
                }
            }
        }
        .displayName("Wetter")
        .description("Zeigt Ort, Temperatur und Regen in Sicht.")
    }
}

struct WeatherControlValue {
    var title: String
    var subtitle: String?
    var symbol: String
}

struct WeatherControlProvider: ControlValueProvider {
    var previewValue: WeatherControlValue {
        WeatherControlValue(title: "Berlin 7°", subtitle: String(localized: "Kein Regen in Sicht"), symbol: "cloud.sun.fill")
    }

    func currentValue() async throws -> WeatherControlValue {
        let place = await widgetPlace(for: nil)
        let coordinates = place.coordinates
        async let forecastRequest = WidgetForecast.forecast(coordinates)
        async let radarRequest = WidgetForecast.radar(coordinates)
        let name = await place.locationName()
        let forecast = (try? await forecastRequest)?.value
        let series = try? await radarRequest

        let now = Date()
        let timeZone = forecast?.locationTimeZone ?? .current
        let subtitle = series.map { RainNowcastSummary.headline(for: RainNowcastSummary.points(from: $0, now: now), now: now, timeZone: timeZone) }
        guard let current = forecast?.current else {
            return WeatherControlValue(title: name, subtitle: subtitle, symbol: "cloud.sun")
        }
        let precipitation = series?.rate(at: now) ?? current.precipitation ?? 0
        let symbol = WeatherSymbol.sfSymbol(
            weathercode: current.weathercode,
            isDay: current.is_day ?? 1,
            isRaining: precipitation > 0,
            precipitation: precipitation
        )
        let title = "\(name) \(SettingService.resolvedUnits.temperatureString(current.temperature))"
        return WeatherControlValue(title: title, subtitle: subtitle, symbol: symbol)
    }
}
#endif
