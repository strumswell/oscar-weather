import SwiftUI

struct StationsView: View {
    @Environment(Weather.self) private var weather
    @Environment(NowPresentationCoordinator.self) private var presentation

    var body: some View {
        let stations = Array(weather.stations.prefix(3))
        if !stations.isEmpty {
            VStack(alignment: .leading) {
                NowSectionHeader(showMore: { presentation.present(.stations(stations[0].id)) }) {
                    Text("Messstationen")
                }
                .padding(.bottom)

                StationsCard(stations: stations, timeZone: weather.forecast.locationTimeZone,
                             isDay: (weather.forecast.current?.is_day ?? 1) > 0) { id in
                    presentation.present(.stations(id))
                }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
            .scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.8)
                    .scaleEffect(phase.isIdentity ? 1 : 0.99)
            }
        }
    }
}

struct StationsCard: View {
    let stations: [Components.Schemas.NearbyStation]
    let timeZone: TimeZone
    var isDay = true
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(stations) { station in
                StationRow(station: station, timeZone: timeZone, isDay: isDay, isFirst: station.id == stations.first?.id) {
                    onSelect(station.id)
                }
            }
        }
        .cardBackground()
        .clipShape(.rect(cornerRadius: 12))
        .cardBorder(RoundedRectangle(cornerRadius: 12))
    }
}

private struct StationRow: View {
    let station: Components.Schemas.NearbyStation
    let timeZone: TimeZone
    let isDay: Bool
    let isFirst: Bool
    let onSelect: () -> Void

    var body: some View {
        let units = SettingService.shared.units
        let rain = station.precipitation_24h_mm.flatMap { $0 >= 0.05 ? units.precipitationString($0) : nil }
        let detail = [stationSubtitle(station, timeZone: timeZone, units: units), rain].compactMap(\.self).joined(separator: " · ")
        let condition = station.current.weather_code.map(WeatherConditionLabel.text(for:))
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: station.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        if let code = station.current.weather_code {
                            Image(decorative: HourlyFormatting.weatherIconName(weatherCode: Double(code), isDay: isDay ? 1 : 0))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                        }
                    }
                    Text(verbatim: detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                StationSparkline(history: station.history, unit: units.temperature)
                    .frame(width: 76, height: 42)

                Text(verbatim: units.preciseTemperatureString(station.current.temperature_c))
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                    .frame(minWidth: 58, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if !isFirst { Divider().padding(.horizontal, 14) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: [station.name, condition, detail, units.preciseTemperatureString(station.current.temperature_c)]
            .compactMap(\.self).joined(separator: ", ")))
        .accessibilityHint(Text("Öffnet Stationsdetails"))
    }
}

extension Weather {
    var headStation: Components.Schemas.NearbyStation? {
        stations.head(favorites: SettingService.shared.favoriteStationIDs)
    }
}
