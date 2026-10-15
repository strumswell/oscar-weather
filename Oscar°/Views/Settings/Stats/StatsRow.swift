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
