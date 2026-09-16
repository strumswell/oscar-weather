import SwiftUI

/// Toggle row inside the "Darstellung" card: title + caption subtitle.
struct LayerToggleRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // Stock switch green; the tab's cascading label tint would paint the
        // track white/black.
        .tint(.green)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
