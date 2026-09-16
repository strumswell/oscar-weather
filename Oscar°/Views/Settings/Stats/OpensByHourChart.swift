import Charts
import SwiftUI

struct OpensByHourChart: View {
    /// Index = hour of day.
    let counts: [Int]

    var body: some View {
        // Each hour spans [h, h+1) so bar 23 stays inside the plot instead of centering on its edge.
        Chart(counts.enumerated(), id: \.offset) { hour, count in
            BarMark(
                xStart: .value("Stunde", Double(hour) + 0.15),
                xEnd: .value("Stunde", Double(hour) + 0.85),
                y: .value("Öffnungen", count)
            )
            .cornerRadius(3)
        }
        .chartXScale(domain: 0...24)
        .chartXAxis {
            AxisMarks(values: [0.0, 6, 12, 18]) { value in
                AxisValueLabel {
                    if let hour = value.as(Double.self) {
                        Text(Int(hour), format: .number.precision(.integerLength(2)))
                    }
                }
            }
        }
        .foregroundStyle(.indigo)
        .frame(height: 140)
        .padding(.vertical, 6)
    }
}
