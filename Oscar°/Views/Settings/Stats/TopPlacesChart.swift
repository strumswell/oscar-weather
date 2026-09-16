import Charts
import SwiftUI

struct TopPlacesChart: View {
    let places: [String: Int]

    var body: some View {
        let top = places.sorted { $0.value > $1.value }.prefix(5)
        Chart(top, id: \.key) { place, count in
            BarMark(x: .value("Abrufe", count), y: .value("Ort", place))
                .cornerRadius(3)
                .annotation(position: .trailing, spacing: 6) {
                    Text(count, format: .number)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { AxisValueLabel() }
        }
        .foregroundStyle(.teal)
        .frame(height: Double(top.count) * 32 + 8)
        .padding(.vertical, 6)
    }
}
