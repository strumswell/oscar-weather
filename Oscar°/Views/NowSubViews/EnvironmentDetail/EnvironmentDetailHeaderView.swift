import SwiftUI

struct EnvironmentDetailHeaderView: View {
    let title: LocalizedStringKey
    let value: String
    let badge: LocalizedStringKey?
    let color: Color
    let subtitle: LocalizedStringKey?

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

        HStack(alignment: .center, spacing: 12) {
            Text(verbatim: value)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            if let badge {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(color.opacity(0.18), in: .capsule)
                    .foregroundStyle(color)
            }
        }

        if let subtitle {
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
