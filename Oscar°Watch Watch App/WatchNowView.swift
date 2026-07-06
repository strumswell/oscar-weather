//
//  WatchNowView.swift
//  Oscar°Watch Watch App
//

import SwiftUI

/// Glanceable current conditions over the simulation: location, temperature,
/// condition, and today's range. Radar overrides the condition line the same
/// way the widgets do — measured rain beats the model's interpolation.
struct WatchNowView: View {
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location

    var body: some View {
        if weather.loadState == .failed && !weather.hasContent {
            retryView
        } else if !weather.hasContent {
            ProgressView()
        } else {
            conditions
        }
    }

    private var conditions: some View {
        let current = weather.forecast.current
        let daily = weather.forecast.daily
        // Same rain signal as HourlyForecastBuilder's "Jetzt" card: radar wins
        // where it has fresh coverage, the model's current value fills the gap.
        let radarRate = weather.precipSeries?.currentRate
        let forecastPrecipitation = current?.precipitation ?? 0
        let isRaining = (radarRate ?? 0) > 0 || forecastPrecipitation > 0
        let rainRate = radarRate ?? forecastPrecipitation

        return VStack(spacing: 0) {
            Text(location.name.isEmpty ? String(localized: "Mein Standort") : location.name)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            Text(roundTemperatureString(temperature: current?.temperature))
                .font(.system(size: 64, weight: .thin, design: .rounded))
                .contentTransition(.numericText())

            Text(conditionDescription(weathercode: current?.weathercode, isRaining: isRaining, rate: rainRate))
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.top, -2)

            Spacer()

            HStack(spacing: 14) {
                Label(
                    roundTemperatureString(temperature: daily?.temperature_2m_max?.first),
                    systemImage: "arrow.up"
                )
                Label(
                    roundTemperatureString(temperature: daily?.temperature_2m_min?.first),
                    systemImage: "arrow.down"
                )
                if rainRate > 0 {
                    Label(
                        String(format: "%.1f mm/h", rainRate),
                        systemImage: "cloud.rain.fill"
                    )
                }
            }
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .labelStyle(WatchCompactLabelStyle())
            .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: .black.opacity(0.35), radius: 2)
    }

    private var retryView: some View {
        VStack(spacing: 8) {
            Image(systemName: "cloud.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Keine Wetterdaten")
                .font(.footnote)
            Button("Erneut versuchen") {
                Task { await weather.refresh(location: location) }
            }
            .font(.footnote)
        }
    }

    /// Weather-code families as short labels; measured or modeled rain lifts a
    /// dry-sky code to a rain description (mirrors the widgets' radar-aware icon).
    private func conditionDescription(weathercode: Double?, isRaining: Bool, rate: Double) -> String {
        var code = Int(weathercode ?? 0)
        if isRaining, code < 51 {
            code = rate >= 2.5 ? 61 : 51
        }

        switch code {
        case 0, 1:
            return String(localized: "Klar")
        case 2:
            return String(localized: "Teils bewölkt")
        case 3:
            return String(localized: "Bedeckt")
        case 45, 48:
            return String(localized: "Nebel")
        case 51...57:
            return String(localized: "Nieselregen")
        case 61...65:
            return String(localized: "Regen")
        case 66, 67:
            return String(localized: "Gefrierender Regen")
        case 71...77, 85, 86:
            return String(localized: "Schneefall")
        case 80...82:
            return String(localized: "Schauer")
        case 95...99:
            return String(localized: "Gewitter")
        default:
            return String(localized: "Bewölkt")
        }
    }
}

/// Icon and text tight together, sized for one row of chips on a 40 mm watch.
private struct WatchCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            configuration.title
        }
    }
}

#Preview {
    WatchNowView()
        .environment(Weather.mock)
        .environment(Location())
        .background(.black)
}
