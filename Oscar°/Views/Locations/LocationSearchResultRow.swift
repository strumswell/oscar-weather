import SwiftUI

struct LocationSearchResultRow: View {
    let result: Components.Schemas.Location
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(result.flagEmoji ?? "📍")
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.displayName)
                        .foregroundStyle(.primary)
                    if let detail = result.detailLine {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }
}
