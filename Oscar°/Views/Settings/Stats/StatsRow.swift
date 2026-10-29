import SwiftUI

struct StatsRow: View {
    let title: LocalizedStringKey
    let value: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            value
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

struct StatsBarRow: View {
    let title: String
    let count: Int
    let most: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            Gauge(value: Double(count), in: 0...Double(max(most, 1))) {}
                .gaugeStyle(.linearCapacity)
                .labelsHidden()
                .tint(tint)
        }
        .accessibilityElement(children: .combine)
    }
}
