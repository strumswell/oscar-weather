import Charts
import SwiftUI

struct OpensByWeekdayChart: View {
    let counts: [Int]
    @State private var selection: String?

    private static let weekdaySymbols = Calendar.current.shortStandaloneWeekdaySymbols
    private static let weekdayNames = Calendar.current.standaloneWeekdaySymbols
    private static let weekdayOrder: [Int] = {
        let first = Calendar.current.firstWeekday - 1
        return (0..<7).map { ($0 + first) % 7 }
    }()

    var body: some View {
        let peak = counts.indices.max { counts[$0] < counts[$1] } ?? 0
        let focus = selection.flatMap { Self.weekdaySymbols.firstIndex(of: $0) } ?? peak

        VStack(alignment: .leading, spacing: 10) {
            StatsChartHeader(
                caption: selection == nil ? "Am häufigsten" : "Ausgewählt",
                title: Text(verbatim: Self.weekdayNames[focus]),
                count: counts[focus]
            )

            Chart(Self.weekdayOrder, id: \.self) { weekday in
                BarMark(
                    x: .value("Wochentag", Self.weekdaySymbols[weekday]),
                    y: .value("Öffnungen", counts[weekday]),
                    width: .ratio(0.6)
                )
                .cornerRadius(4)
                .foregroundStyle(.indigo.opacity(weekday == focus ? 1 : 0.35))
            }
            .chartXScale(domain: Self.weekdayOrder.map { Self.weekdaySymbols[$0] })
            .chartXSelection(value: $selection)
            .chartXAxis {
                AxisMarks { AxisValueLabel() }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                }
            }
            .frame(height: 130)
        }
        .animation(.snappy, value: focus)
    }
}
