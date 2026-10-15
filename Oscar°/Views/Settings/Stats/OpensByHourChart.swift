import Charts
import SwiftUI

struct OpensByHourChart: View {
    let counts: [Int]
    @State private var selection: Double?

    var body: some View {
        let peak = counts.indices.max { counts[$0] < counts[$1] } ?? 0
        let focus = selection.map { min(max(Int($0), 0), 23) } ?? peak

        VStack(alignment: .leading, spacing: 10) {
            StatsChartHeader(
                caption: selection == nil ? "Am häufigsten" : "Ausgewählt",
                title: Text(Self.hours(focus).formatted(.interval.hour())),
                count: counts[focus]
            )

            Chart(counts.enumerated(), id: \.offset) { hour, count in
                BarMark(
                    xStart: .value("Stunde", Double(hour) + 0.12),
                    xEnd: .value("Stunde", Double(hour) + 0.88),
                    y: .value("Öffnungen", count)
                )
                .cornerRadius(4)
                .foregroundStyle(.indigo.opacity(hour == focus ? 1 : 0.35))
            }
            .chartXScale(domain: 0...24)
            .chartXSelection(value: $selection)
            .chartXAxis {
                AxisMarks(values: [0.0, 6, 12, 18]) { value in
                    AxisValueLabel {
                        if let hour = value.as(Double.self) {
                            Text(Self.hours(Int(hour)).lowerBound, format: .dateTime.hour())
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                }
            }
            .frame(height: 150)
        }
        .animation(.snappy, value: focus)
    }

    private static func hours(_ hour: Int) -> Range<Date> {
        let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return start..<start.addingTimeInterval(3600)
    }
}
