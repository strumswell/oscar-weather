import SwiftUI
import WidgetKit

struct DailyForecastEntryView: View {
    var entry: DailyForecastEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isCompact: Bool { family == .systemSmall }
    private var dayCount: Int { family == .systemLarge ? 9 : 4 }
    private var rowSpacing: CGFloat { family == .systemLarge ? 12 : (isCompact ? 4 : 7) }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            Text(entry.location)
                .font(isCompact ? .subheadline : .headline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.bottom, family == .systemLarge ? 4 : 2)

            ForEach(entry.days.prefix(dayCount)) { day in
                if isCompact {
                    DailyForecastCompactRow(day: day)
                        .frame(maxHeight: .infinity)
                } else {
                    DailyForecastRow(
                        day: day,
                        minTemp: entry.minTemp,
                        maxTemp: entry.maxTemp,
                        temperatureUnit: entry.temperatureUnit
                    )
                    .frame(maxHeight: family == .systemLarge ? .infinity : nil)
                }
            }
        }
        .padding(family == .systemLarge ? 16 : 12)
        .foregroundStyle(.white)
        .widgetAccentable()
        .containerBackground(for: .widget) {
            entry.backgroundGradient
                .opacity(renderingMode == .accented ? 0 : 1)
        }
    }
}

struct DailyForecastRow: View {
    let day: DayForecast
    let minTemp: Double
    let maxTemp: Double
    let temperatureUnit: String

    var body: some View {
        HStack(spacing: 10) {
            Text(day.weekday)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 48, alignment: .leading)

            Image(systemName: day.icon)
                .symbolRenderingMode(.multicolor)
                .font(.body)
                .frame(width: 30, height: 22)

            Text(roundTemperatureString(temperature: day.low))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 34, alignment: .trailing)

            TemperatureRangeView(
                low: day.low,
                high: day.high,
                focusLow: nil,
                focusHigh: nil,
                minTemp: minTemp,
                maxTemp: maxTemp,
                unit: temperatureUnit
            )
            .frame(height: 6)

            Text(roundTemperatureString(temperature: day.high))
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(width: 34, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(day.weekday): \(roundTemperatureString(temperature: day.low)) bis \(roundTemperatureString(temperature: day.high))")
        )
    }
}

/// Compact row for the small widget — no range bar, just weekday · icon · high/low.
struct DailyForecastCompactRow: View {
    let day: DayForecast

    var body: some View {
        HStack(spacing: 6) {
            Text(day.weekday)
                .font(.footnote)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 36, alignment: .leading)

            Image(systemName: day.icon)
                .symbolRenderingMode(.multicolor)
                .font(.footnote)
                .frame(width: 22, height: 16)

            Spacer(minLength: 2)

            Text(roundTemperatureString(temperature: day.high))
                .font(.footnote)
                .fontWeight(.semibold)
                .monospacedDigit()

            Text(roundTemperatureString(temperature: day.low))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(day.weekday): \(roundTemperatureString(temperature: day.low)) bis \(roundTemperatureString(temperature: day.high))")
        )
    }
}
