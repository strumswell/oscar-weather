import SwiftUI

struct StatsChartHeader: View {
    let caption: LocalizedStringKey
    let title: Text
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                title
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Öffnungen")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(count, format: .number)
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
