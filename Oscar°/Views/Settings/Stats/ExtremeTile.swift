import SwiftUI

struct ExtremeTile: View {
    let title: LocalizedStringKey
    let extreme: UsageStats.Extreme?
    let tint: Color
    var format: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Capsule()
                    .fill(tint)
                    .frame(width: 4, height: 12)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let extreme {
                Text(verbatim: format(extreme.value))
                    .font(.title2.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: whereAndWhen(extreme))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(verbatim: "–")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func whereAndWhen(_ extreme: UsageStats.Extreme) -> String {
        let day = extreme.date.formatted(.dateTime.day().month().year())
        return extreme.place.isEmpty ? day : "\(extreme.place) · \(day)"
    }
}
