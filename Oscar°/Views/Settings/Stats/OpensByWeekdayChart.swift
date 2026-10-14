import Charts
import SwiftUI

struct OpensByWeekdayChart: View {
    let counts: [Int]

    private static let weekdaySymbols = Calendar.current.shortStandaloneWeekdaySymbols

    private static let weekdayOrder: [Int] = {
        let first = Calendar.current.firstWeekday - 1
        return (0..<7).map { ($0 + first) % 7 }
    }()

    var body: some View {
        Chart(Self.weekdayOrder, id: \.self) { weekday in
            BarMark(x: .value("Wochentag", Self.weekdaySymbols[weekday]), y: .value("Öffnungen", counts[weekday]))
                .cornerRadius(3)
        }
        .chartXScale(domain: Self.weekdayOrder.map { Self.weekdaySymbols[$0] })
        .chartXAxis {
            AxisMarks { AxisValueLabel() }
        }
        .foregroundStyle(.indigo)
        .frame(height: 120)
        .padding(.vertical, 6)
    }
}
