// Favorite or nearest station: home, lock screen and watch families.
import SwiftUI
import WidgetKit

struct StationWidget: Widget {
    let kind = "StationWidget"

    var body: some WidgetConfiguration {
        placeConfiguration(kind: kind, source: StationsProvider()) { entry in
            StationWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Station"))
        .description(String(localized: "Gemessene Werte deiner Favoritenstation oder der nächsten Station."))
        #if os(iOS)
        .contentMarginsDisabled()
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
        #else
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
        #endif
    }
}

struct StationWidgetView: View {
    let entry: StationsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                StationCircularView(station: entry.head)
            case .accessoryRectangular:
                StationRectangularView(station: entry.head)
            #if os(iOS)
            case .systemMedium:
                StationHomeView(station: entry.head, isDay: entry.isDay, isMedium: true, timeZone: entry.timeZone)
            default:
                StationHomeView(station: entry.head, isDay: entry.isDay, isMedium: false, timeZone: entry.timeZone)
            #else
            default:
                EmptyView()
            #endif
            }
        }
        .widgetURL(.oscarPlace(entry.cityID))
    }
}

struct StationSky: View {
    let isDay: Bool
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        (isDay ? .calmDay : LinearGradient(colors: [Color(hex: 0x0B1430), Color(hex: 0x26365F)], startPoint: .top, endPoint: .bottom))
            .opacity(renderingMode == .accented ? 0 : 1)
    }
}

struct NoStationView: View {
    var body: some View {
        Text("Keine Messstation in der Nähe")
            .font(.footnote.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StationHomeView: View {
    let station: Components.Schemas.NearbyStation?
    let isDay: Bool
    let isMedium: Bool
    let timeZone: TimeZone

    var body: some View {
        Group {
            if let station {
                let cells = stationCells(station)
                if isMedium && !cells.isEmpty {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 0) {
                            StationHeadline(station: station, isDay: isDay, timeZone: timeZone, temperatureSize: 34)
                            Spacer(minLength: 4)
                            StationSparkline(history: station.history, unit: SettingService.resolvedUnits.temperature)
                                .frame(height: 44)
                        }
                        .frame(width: 140)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                                  alignment: .leading, spacing: 10) {
                            ForEach(cells, id: \.label) { cell in
                                StationCellView(cell: cell)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        StationHeadline(station: station, isDay: isDay, timeZone: timeZone, temperatureSize: 38)
                        Spacer(minLength: 0)
                        StationSparkline(history: station.history, unit: SettingService.resolvedUnits.temperature)
                            .frame(minHeight: 30, maxHeight: 48)
                        HStack {
                            Text("−24 h")
                            Spacer()
                            Text("jetzt")
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    }
                    .padding(14)
                }
            } else {
                NoStationView()
                    .padding(14)
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .containerBackground(for: .widget) {
            StationSky(isDay: isDay)
        }
    }
}

private struct StationHeadline: View {
    let station: Components.Schemas.NearbyStation
    let isDay: Bool
    let timeZone: TimeZone
    let temperatureSize: CGFloat

    var body: some View {
        let units = SettingService.resolvedUnits
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: station.name)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            Text(verbatim: stationSubtitle(station, timeZone: timeZone, units: units))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(verbatim: units.preciseTemperatureString(station.current.temperature_c))
                    .font(.system(size: temperatureSize))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                if let code = station.current.weather_code {
                    Image(systemName: WeatherSymbol.sfSymbol(weathercode: Double(code), isDay: isDay))
                        .font(.system(size: temperatureSize * 0.45))
                        .accessibilityHidden(true)
                }
            }
            .padding(.top, 2)
        }
    }
}

private struct StationCell {
    let label: String
    let value: String
    let detail: String?
}

private struct StationCellView: View {
    let cell: StationCell

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: cell.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: cell.value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            if let detail = cell.detail {
                Text(verbatim: detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private func stationCells(_ station: Components.Schemas.NearbyStation) -> [StationCell] {
    let units = SettingService.resolvedUnits
    let current = station.current
    var cells: [StationCell] = []
    if let speed = current.wind_speed_ms {
        let parts = [current.wind_gust_ms.map { String(localized: "Böen \(units.windNumber($0 * 3.6))") },
                     current.wind_direction_deg.map(compassDirection)].compactMap(\.self)
        cells.append(StationCell(label: String(localized: "Wind"), value: units.windString(speed * 3.6),
                                 detail: parts.isEmpty ? nil : parts.joined(separator: " · ")))
    }
    if let humidity = current.humidity_pct {
        cells.append(StationCell(label: String(localized: "Feuchte"), value: "\(Int(humidity.rounded())) %",
                                 detail: current.dew_point_c.map { String(localized: "Taupunkt \(units.preciseTemperatureString($0))") }))
    }
    if let pressure = current.pressure_hpa {
        cells.append(StationCell(label: String(localized: "Druck"), value: units.pressureString(pressure),
                                 detail: pressureTrend(station.history, unit: units.pressure)))
    }
    if let rain = station.precipitation_24h_mm {
        let lastHour = station.history.filter {
            $0.time > station.last_report_at.addingTimeInterval(-3600) && ($0.precipitation_period_min ?? 60) <= 60
        }.compactMap(\.precipitation_mm)
        cells.append(StationCell(label: String(localized: "Regen 24 h"), value: units.precipitationString(rain),
                                 detail: lastHour.isEmpty ? nil : String(localized: "letzte 1 h: \(units.precipitationNumber(lastHour.reduce(0, +)))")))
    }
    return cells
}

private func pressureTrend(_ history: [Components.Schemas.StationReading], unit: PressureUnit) -> String? {
    let pressures = history.compactMap { reading in reading.pressure_hpa.map { (time: reading.time, value: $0) } }
    guard let last = pressures.last else { return nil }
    let target = last.time.addingTimeInterval(-3 * 3600)
    guard let earlier = pressures.min(by: { abs($0.time.timeIntervalSince(target)) < abs($1.time.timeIntervalSince(target)) }),
          abs(earlier.time.timeIntervalSince(target)) <= 1800 else { return nil }
    let delta = (unit.value(fromHectopascals: last.value) - unit.value(fromHectopascals: earlier.value)).formatted(
        .number.precision(.fractionLength(unit.fractionDigits + 1)).sign(strategy: .always(includingZero: false)))
    return String(localized: "\(delta) in 3 h")
}

private struct StationRectangularView: View {
    let station: Components.Schemas.NearbyStation?

    var body: some View {
        Group {
            if let station {
                let units = SettingService.resolvedUnits
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(verbatim: station.name)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: units.preciseTemperatureString(station.current.temperature_c))
                            .monospacedDigit()
                            .layoutPriority(1)
                    }
                    .font(.headline)
                    StationSparkline(history: station.history, unit: units.temperature)
                        .frame(maxHeight: .infinity)
                }
            } else {
                Text("Keine Messstation in der Nähe")
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .containerBackground(.clear, for: .widget)
    }
}

private struct StationCircularView: View {
    let station: Components.Schemas.NearbyStation?

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("gemessen")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: SettingService.resolvedUnits.preciseTemperatureString(station?.current.temperature_c))
                    .font(.system(size: 18, weight: .semibold))
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .combine)
        .containerBackground(.clear, for: .widget)
    }
}

#if os(iOS)
#Preview("Small", as: .systemSmall) {
    StationWidget()
} timeline: {
    StationsEntry.sample
    StationsEntry.empty
}

#Preview("Medium", as: .systemMedium) {
    StationWidget()
} timeline: {
    StationsEntry.sample
}
#endif

#Preview("Rectangular", as: .accessoryRectangular) {
    StationWidget()
} timeline: {
    StationsEntry.sample
    StationsEntry.empty
}

#Preview("Circular", as: .accessoryCircular) {
    StationWidget()
} timeline: {
    StationsEntry.sample
}
