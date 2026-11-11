import Charts
import Foundation
import SwiftUI

extension Binding where Value == Date? {
    static func snapped(to interval: TimeInterval, _ source: Binding<Date?>) -> Binding<Date?> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in
                let snapped = newValue.map { date in
                    Date(timeIntervalSince1970: (date.timeIntervalSince1970 / interval).rounded() * interval)
                }
                if snapped != source.wrappedValue {
                    source.wrappedValue = snapped
                }
            }
        )
    }
}

enum HourlyChartUtilities {
    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar
    }

    static func dayChangeIndices(time: [Double], calendar: Calendar) -> [Int] {
        guard time.count > 1 else { return [] }

        return time.indices.dropFirst().filter { index in
            let previousDate = Date(timeIntervalSince1970: time[index - 1])
            let currentDate = Date(timeIntervalSince1970: time[index])
            return !calendar.isDate(previousDate, inSameDayAs: currentDate)
        }
    }

    static func dayAbbreviation(from date: Date, timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated))
    }

    static func hourString(from date: Date, timeZone: TimeZone) -> String {
        SettingService.formattedTime(date, timeZone: timeZone, showsMinutes: false)
    }

    static func niceStep(_ raw: Double) -> Double {
        let magnitude = pow(10, floor(log10(max(raw, 0.0001))))
        let normalized = raw / magnitude
        if normalized < 1.5 { return magnitude }
        if normalized < 3.5 { return 2 * magnitude }
        if normalized < 7.5 { return 5 * magnitude }
        return 10 * magnitude
    }
}

extension HourlyChartUtilities {
    @ChartContentBuilder
    static func daySeparatorMarks(time: [Double], timeZone: TimeZone) -> some ChartContent {
        ForEach(dayChangeIndices(time: time, calendar: calendar(in: timeZone)), id: \.self) { index in
            RuleMark(x: .value("Hour", Date(timeIntervalSince1970: time[index])))
                .foregroundStyle(.gray.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                .annotation(
                    position: .topTrailing,
                    spacing: 8,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    Text(dayAbbreviation(from: Date(timeIntervalSince1970: time[index]), timeZone: timeZone))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: .capsule)
                }
        }
    }

    @ChartContentBuilder
    static func currentPointMark(x: Date, series: String, value: Double) -> some ChartContent {
        PointMark(x: .value("Current Hour", x), y: .value(series, value))
            .symbol(.circle)
            .symbolSize(90)
            .foregroundStyle(.black)

        PointMark(x: .value("Current Hour", x), y: .value(series, value))
            .symbol(.circle)
            .symbolSize(42)
            .foregroundStyle(.white)
    }

    @AxisContentBuilder
    static func sixHourAxisMarks(timeZone: TimeZone) -> some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: 6, calendar: calendar(in: timeZone))) { value in
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(hourString(from: date, timeZone: timeZone))
                }
            }
            AxisGridLine()
            AxisTick()
        }
    }
}

struct ChartLegendView: View {
    let items: [(label: String, color: Color)]
    var minimumItemWidth: CGFloat = 74

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumItemWidth), spacing: 12)], alignment: .leading, spacing: 8) {
            ForEach(items.enumerated(), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 8, height: 8)

                    Text(verbatim: item.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
