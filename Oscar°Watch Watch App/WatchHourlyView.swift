//
//  WatchHourlyView.swift
//  Oscar°Watch Watch App
//

import SwiftUI

/// The next 12 hours as card rows, built by the shared radar-aware forecast
/// builder (leading "Jetzt" card, sunrise/sunset rows included).
struct WatchHourlyView: View {
    @Environment(Weather.self) private var weather: Weather

    // 12 forecast hours plus whatever sun events fall in between.
    private static let maxRows = 14

    var body: some View {
        let timeZone = TimeZone(secondsFromGMT: weather.forecast.utc_offset_seconds ?? 0) ?? .current
        let hourFormatter = Self.hourFormatter(timeZone: timeZone)
        let items = HourlyForecastBuilder.makeItems(
            forecast: weather.forecast,
            precipSeries: weather.precipSeries,
            isLoading: weather.isLoading
        ).prefix(Self.maxRows)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                Text("Stündlich")
                    .font(.title3.weight(.semibold))
                    .padding(.bottom, 2)

                if items.isEmpty {
                    Text("Keine Daten")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(items)) { item in
                        switch item {
                        case .forecast(let forecast):
                            forecastRow(forecast, hourFormatter: hourFormatter)
                        case .sunEvent(let sunEvent):
                            sunEventRow(sunEvent)
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func forecastRow(_ item: HourlyForecastItem, hourFormatter: DateFormatter) -> some View {
        HStack(spacing: 6) {
            Text(hourLabel(for: item, formatter: hourFormatter))
                .font(.system(size: 15, weight: item.isNow ? .bold : .medium, design: .rounded))
                .frame(width: 44, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Image(item.iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)

            if item.precipitationValue > 0 {
                Text(item.precipitation)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 2)

            Text(item.temperature)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(.white.opacity(item.isNow ? 0.16 : 0.08), in: .rect(cornerRadius: 10))
    }

    private func sunEventRow(_ item: HourlySunEventItem) -> some View {
        HStack(spacing: 6) {
            Text(item.time)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Image(item.kind.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)

            Spacer(minLength: 2)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
    }

    /// Compact hour label: "14" instead of "14 Uhr" — the row is too narrow
    /// for the long form. 12-hour clocks keep their "2 PM".
    private func hourLabel(for item: HourlyForecastItem, formatter: DateFormatter) -> String {
        if item.isNow {
            return String(localized: "Jetzt")
        }
        return formatter.string(from: Date(timeIntervalSince1970: item.timestamp))
    }

    private static func hourFormatter(timeZone: TimeZone) -> DateFormatter {
        let uses12h: Bool
        switch SettingService.resolvedTimeFormatPreference {
        case .h12:
            uses12h = true
        case .h24:
            uses12h = false
        default:
            let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent)
            uses12h = template?.contains("a") ?? false
        }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timeZone
        formatter.dateFormat = uses12h ? "h a" : "H"
        return formatter
    }
}

#Preview {
    WatchHourlyView()
        .environment(Weather.mock)
        .environment(Location())
        .background(.black)
}
