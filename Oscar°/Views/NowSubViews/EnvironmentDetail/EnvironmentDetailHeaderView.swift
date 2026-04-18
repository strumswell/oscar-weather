import SwiftUI

struct EnvironmentDetailHeaderView: View {
    let title: LocalizedStringKey
    let value: String
    let badge: String
    let color: Color
    let subtitle: String?

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

        HStack(alignment: .center, spacing: 12) {
            Text(verbatim: value)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(LocalizedStringKey(badge))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(color.opacity(0.18), in: .capsule)
                .foregroundStyle(color)
        }

        if let subtitle {
            Text(verbatim: subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
