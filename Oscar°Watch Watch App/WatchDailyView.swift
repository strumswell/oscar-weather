//
//  WatchDailyView.swift
//  Oscar°Watch Watch App
//

import SwiftUI

/// Seven days with the shared temperature-range bars, scaled to the
/// week's overall min/max like the iPhone daily list.
struct WatchDailyView: View {
    @Environment(Weather.self) private var weather: Weather

    private static let maxDays = 7

    var body: some View {
        let daily = weather.forecast.daily
        let count = dayCount(daily)
        let scale = temperatureScale(daily, count: count)
        let unit = weather.forecast.daily_units?.temperature_2m_min ?? "°C"
        let timeZone = TimeZone(secondsFromGMT: weather.forecast.utc_offset_seconds ?? 0) ?? .current
        let weekdayFormatter = Self.weekdayFormatter(timeZone: timeZone)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                Text("7 Tage")
                    .font(.title3.weight(.semibold))
                    .padding(.bottom, 2)

                if count == 0 {
                    Text("Keine Daten")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(0..<count, id: \.self) { day in
                        row(
                            day: day,
                            daily: daily,
                            scale: scale,
                            unit: unit,
                            weekdayFormatter: weekdayFormatter
                        )
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func row(
        day: Int,
        daily: Components.Schemas.DailyResponse?,
        scale: (min: Double, max: Double),
        unit: String,
        weekdayFormatter: DateFormatter
    ) -> some View {
        let low = daily?.temperature_2m_min?[day] ?? 0
        let high = daily?.temperature_2m_max?[day] ?? 0
        let date = Date(timeIntervalSince1970: daily?.time[day] ?? 0)

        return HStack(spacing: 6) {
            Text(day == 0 ? String(localized: "Heute") : weekdayFormatter.string(from: date))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .frame(width: 42, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Image(weatherIcon(for: daily?.weathercode?[day]))
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)

            Text(roundTemperatureString(temperature: low))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)

            TemperatureRangeView(
                low: low,
                high: high,
                focusLow: nil,
                focusHigh: nil,
                minTemp: scale.min,
                maxTemp: scale.max,
                unit: unit
            )
            .frame(height: 5)

            Text(roundTemperatureString(temperature: high))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(width: 30, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
    }

    private func dayCount(_ daily: Components.Schemas.DailyResponse?) -> Int {
        guard let daily else { return 0 }
        return min(
            Self.maxDays,
            [
                daily.time.count,
                daily.temperature_2m_min?.count ?? 0,
                daily.temperature_2m_max?.count ?? 0
            ].min() ?? 0
        )
    }

    private func temperatureScale(
        _ daily: Components.Schemas.DailyResponse?,
        count: Int
    ) -> (min: Double, max: Double) {
        guard count > 0,
              let lows = daily?.temperature_2m_min?.prefix(count),
              let highs = daily?.temperature_2m_max?.prefix(count),
              let min = lows.min(),
              let max = highs.max()
        else {
            return (0, 1)
        }
        return (min, max)
    }

    /// Abbreviated weekday ("Mo.", "Mon") — full names truncate in the column.
    private static func weekdayFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("E")
        return formatter
    }

    /// Daily weather code to icon asset, mirrors DailyView.getWeatherIcon.
    private func weatherIcon(for code: Double?) -> String {
        switch Int(code ?? 0) {
        case 0, 1:
            return "01d"
        case 2:
            return "02d"
        case 3:
            return "04d"
        case 45, 48:
            return "50d"
        case 51:
            return "10d"
        case 71, 73, 75, 77, 85, 86:
            return "13d"
        case 95, 96, 99:
            return "11d"
        default:
            return "09d"
        }
    }
}

#Preview {
    WatchDailyView()
        .environment(Weather.mock)
        .environment(Location())
        .background(.black)
}
