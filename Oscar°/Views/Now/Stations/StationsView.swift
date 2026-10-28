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

                StationSparkline(history: station.history)
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

private struct StationSparkline: View {
    let history: [Components.Schemas.StationReading]

    private static let labelBand: CGFloat = 11

    var body: some View {
        let temperatureUnit = SettingService.shared.temperatureUnit
        Canvas { context, size in
            let points = history.compactMap { reading in
                reading.temperature_c.map { (reading.time.timeIntervalSince1970, $0) }
            }
            guard points.count > 1, let last = points.last,
                  let lowPoint = points.min(by: { $0.1 < $1.1 }), let highPoint = points.max(by: { $0.1 < $1.1 }) else { return }
            let low = lowPoint.1
            let span = max(highPoint.1 - low, 1)
            let start = points[0].0
            let duration = max(last.0 - start, 1)
            let top = Self.labelBand
            let height = size.height - 2 * Self.labelBand
            func position(_ point: (Double, Double)) -> CGPoint {
                CGPoint(
                    x: 2 + (point.0 - start) / duration * (size.width - 5),
                    y: top + (1 - (point.1 - low) / span) * height)
            }
            var line = Path()
            line.addLines(points.map(position))
            context.stroke(line, with: .color(.primary.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            let end = position(last)
            context.fill(Path(ellipseIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)), with: .color(.primary))

            guard highPoint.1 > low else { return }
            for (point, isHigh) in [(highPoint, true), (lowPoint, false)] {
                let label = context.resolve(
                    Text(verbatim: temperatureUnit.string(point.1))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6)))
                let labelSize = label.measure(in: size)
                let anchor = position(point)
                let labelX = min(max(anchor.x, labelSize.width / 2), size.width - labelSize.width / 2)
                context.draw(label, at: CGPoint(x: labelX, y: isHigh ? anchor.y - 2 : anchor.y + 2),
                             anchor: isHigh ? .bottom : .top)
            }
        }
        .accessibilityHidden(true)
    }
}

extension Weather {
    var headStation: Components.Schemas.NearbyStation? {
        let favorites = SettingService.shared.favoriteStationIDs
        let reporting = stations.filter { $0.current.temperature_c != nil }
        return reporting.first { favorites.contains($0.id) } ?? reporting.first
    }
}

func stationSubtitle(_ station: Components.Schemas.NearbyStation, timeZone: TimeZone, units: Units) -> String {
    let time = station.last_report_at.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    return "\(units.distanceString(station.distance_km)) \(compassDirection(station.bearing_deg)) · \(time)"
}
