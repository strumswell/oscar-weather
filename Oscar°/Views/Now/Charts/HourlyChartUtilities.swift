import Charts
import Foundation
import SwiftUI

extension Binding where Value == Date? {
    /// Wraps a `.chartXSelection` binding so the continuous drag samples only
    /// invalidate SwiftUI when the selection reaches a different data step.
    /// The cursor and tooltip resolve to the nearest hour anyway, so the
    /// per-sample writes (60–120 Hz) re-rendered the entire chart for
    /// identical output — that was the scrub lag.
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
    static func dayChangeIndices(time: [Double], calendar: Calendar = .current) -> [Int] {
        guard time.count > 1 else { return [] }

        return time.indices.dropFirst().filter { index in
            let previousDate = Date(timeIntervalSince1970: time[index - 1])
            let currentDate = Date(timeIntervalSince1970: time[index])
            return !calendar.isDate(previousDate, inSameDayAs: currentDate)
        }
    }

    static func dayAbbreviation(from date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    static func hourString(from date: Date) -> String {
        SettingService.formattedTime(date, showsMinutes: false)
    }
}

extension HourlyChartUtilities {
    /// Dashed rule with a weekday badge at every day change.
    @ChartContentBuilder
    static func daySeparatorMarks(time: [Double]) -> some ChartContent {
        ForEach(dayChangeIndices(time: time), id: \.self) { index in
            RuleMark(x: .value("Hour", Date(timeIntervalSince1970: time[index])))
                .foregroundStyle(.gray.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                .annotation(
                    position: .topTrailing,
                    spacing: 8,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    Text(dayAbbreviation(from: Date(timeIntervalSince1970: time[index])))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: .capsule)
                }
        }
    }

    /// Black ring with a white dot marking the current hour on a series.
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
    static func sixHourAxisMarks() -> some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: 6)) { value in
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(hourString(from: date))
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
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
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
