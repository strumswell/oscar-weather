import Charts
import SwiftUI

struct TopPlacesChart: View {
    let places: [String: Int]

    var body: some View {
        let top = places.sorted { $0.value > $1.value }.prefix(5)
        Chart(top, id: \.key) { place, count in
            BarMark(x: .value("Abrufe", count), y: .value("Ort", place), height: .fixed(14))
                .cornerRadius(4)
                .foregroundStyle(.teal.opacity(place == top.first?.key ? 1 : 0.5))
                .annotation(position: .trailing, spacing: 6) {
                    Text(count, format: .number)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { AxisValueLabel().font(.subheadline) }
        }
        .frame(height: Double(top.count) * 34)
    }
}
