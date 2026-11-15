// The three nearest stations, like the Messstationen card in the app.
import SwiftUI
import WidgetKit

struct StationsListWidget: Widget {
    let kind = "StationsListWidget"

    var body: some WidgetConfiguration {
        placeConfiguration(kind: kind, source: StationsProvider()) { entry in
            StationsListView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName(String(localized: "Stationen"))
        .description(String(localized: "Die drei nächsten Messstationen mit Temperaturverlauf."))
        .supportedFamilies([.systemMedium])
    }
}

private struct StationsListView: View {
    let entry: StationsEntry

    var body: some View {
        let stations = Array(entry.stations.prefix(3))
        Group {
            if stations.isEmpty {
                NoStationView()
            } else {
                VStack(spacing: 0) {
                    ForEach(stations) { station in
                        StationsListRow(station: station, timeZone: entry.timeZone, isFirst: station.id == stations.first?.id)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            StationSky(isDay: entry.isDay)
        }
        .widgetURL(.oscarPlace(entry.cityID))
    }
}

private struct StationsListRow: View {
    let station: Components.Schemas.NearbyStation
    let timeZone: TimeZone
    let isFirst: Bool

    var body: some View {
        let units = SettingService.resolvedUnits
        let rain = station.precipitation_24h_mm.flatMap { $0 >= 0.05 ? units.precipitationString($0) : nil }
        let detail = [stationSubtitle(station, timeZone: timeZone, units: units), rain].compactMap(\.self).joined(separator: " · ")
        let temperature = units.preciseTemperatureString(station.current.temperature_c)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: station.name)
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            StationSparkline(history: station.history, unit: units.temperature, showsExtremes: false)
                .frame(width: 64, height: 26)

            Text(verbatim: temperature)
                .font(.title3.weight(.medium))
                .monospacedDigit()
                .frame(minWidth: 52, alignment: .trailing)
                .widgetAccentable()
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [station.name, detail, temperature].joined(separator: ", ")))
    }
}

#Preview("Medium", as: .systemMedium) {
    StationsListWidget()
} timeline: {
    StationsEntry.sample
    StationsEntry.empty
}
