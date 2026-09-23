import SwiftUI

/// "Messstationen": the three nearest stations with fresh readings. Hidden when there
/// are none (outside Europe, or the fetch failed).
struct StationsView: View {
    @Environment(Weather.self) private var weather
    @Environment(NowPresentationCoordinator.self) private var presentation

    var body: some View {
        let stations = Array(weather.stations.prefix(3))
        if !stations.isEmpty {
            VStack(alignment: .leading) {
                Text("Messstationen")
                    .font(.title3)
                    .bold()
                    .foregroundStyle(.primary)
                    .padding([.leading, .bottom])

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

/// Also staged in the layout preview, hence the injected tap action.
struct StationsCard: View {
    let stations: [WeatherStation]
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
    let station: WeatherStation
    let timeZone: TimeZone
    let isDay: Bool
    let isFirst: Bool
    let onSelect: () -> Void

    var body: some View {
        let units = StationUnits()
        // Rain only when there was some; rounded to 0,0 it says nothing.
        let rain = station.precipitation24h.flatMap { $0 >= 0.05 ? units.precipitationString($0) : nil }
        let detail = [stationSubtitle(station, timeZone: timeZone), rain].compactMap(\.self).joined(separator: " · ")
        let condition = station.current.weatherCode.map(WeatherConditionLabel.text(for:))
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: station.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        if let code = station.current.weatherCode {
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

                Text(verbatim: units.temperatureString(station.current.temperature))
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
        .accessibilityLabel(Text(verbatim: [station.name, condition, detail, units.temperatureString(station.current.temperature)]
            .compactMap(\.self).joined(separator: ", ")))
        .accessibilityHint(Text("Öffnet Stationsdetails"))
    }
}

/// Temperature over the last 24 h, scaled to its own range; the dot marks the newest reading and
/// quiet labels mark the high and the low.
private struct StationSparkline: View {
    let history: [StationReading]

    /// Room above and below the line for the high/low labels.
    private static let labelBand: CGFloat = 11

    var body: some View {
        let units = StationUnits()
        Canvas { context, size in
            let points = history.compactMap { reading in
                reading.temperature.map { (reading.time.timeIntervalSince1970, $0) }
            }
            guard points.count > 1, let last = points.last,
                  let lowPoint = points.min(by: { $0.1 < $1.1 }), let highPoint = points.max(by: { $0.1 < $1.1 }) else { return }
            let low = lowPoint.1
            let span = max(highPoint.1 - low, 1)
            // Stretched over the readings there are, like the y scale: a 3-hourly station
            // with 19 h of history would otherwise start with an empty gap.
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
                    Text(verbatim: "\(Int(units.temperature(point.1).rounded()))°")
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

/// "5,8 km S · 22:00": distance and direction from the place, then the reading's time
/// (a clock time rather than "44 min ago", which would need a ticking timer).
func stationSubtitle(_ station: WeatherStation, timeZone: TimeZone) -> String {
    let distance = station.distanceKm.formatted(.number.precision(.fractionLength(1)))
    let time = station.lastReportAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    return "\(distance) km \(compassDirection(station.bearing)) · \(time)"
}

/// Station values arrive in SI; the display follows the unit settings.
@MainActor
struct StationUnits {
    let temperatureUnit = ClimateTemperatureUnit(settingValue: SettingService.shared.temperatureUnit)
    let windUnit = WindSpeedUnit(settingValue: SettingService.shared.windSpeedUnit)
    let inches = SettingService.shared.precipitationUnit.lowercased() == "inch"

    var precipitationUnit: String { inches ? "inch" : "mm" }

    func temperature(_ celsius: Double) -> Double { temperatureUnit.value(fromCelsius: celsius) }

    /// "15,7°", one decimal: measured values are that precise, forecasts are not.
    func temperatureString(_ celsius: Double?) -> String {
        guard let celsius else { return "–" }
        return "\(temperature(celsius).formatted(.number.precision(.fractionLength(1))))°"
    }

    func wind(_ metersPerSecond: Double) -> Double {
        switch windUnit {
        case .ms: metersPerSecond
        case .kmh: metersPerSecond * 3.6
        case .mph: metersPerSecond * 2.23694
        case .kn: metersPerSecond * 1.94384
        case .bft: Double(BeaufortScale.force(forKilometersPerHour: metersPerSecond * 3.6))
        }
    }

    func windString(_ metersPerSecond: Double?) -> String {
        WindSpeedFormatter.string(metersPerSecond.map(wind), unit: windUnit.displayUnit)
    }

    func precipitation(_ millimeters: Double) -> Double { inches ? millimeters / 25.4 : millimeters }

    func precipitationString(_ millimeters: Double?) -> String {
        guard let millimeters else { return "–" }
        return HourlyFormatting.precipitationString(value: precipitation(millimeters), unit: precipitationUnit)
    }
}
