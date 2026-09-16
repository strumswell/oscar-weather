import SwiftUI

struct ExtremeRow: View {
    let title: LocalizedStringKey
    let extreme: UsageStats.Extreme?
    let icon: String
    let tint: Color

    var body: some View {
        Label {
            LabeledContent {
                if let extreme {
                    Text(verbatim: value(extreme))
                } else {
                    Text(verbatim: "–")
                }
            } label: {
                Text(title)
                if let extreme {
                    Text(verbatim: whereAndWhen(extreme))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint)
        }
    }

    private func value(_ extreme: UsageStats.Extreme) -> String {
        let number = extreme.value.formatted(.number.precision(.fractionLength(0...1)))
        return extreme.unit.isEmpty ? number : "\(number) \(extreme.unit)"
    }

    private func whereAndWhen(_ extreme: UsageStats.Extreme) -> String {
        let day = extreme.date.formatted(.dateTime.day().month())
        return extreme.place.isEmpty ? day : "\(extreme.place) · \(day)"
    }
}
