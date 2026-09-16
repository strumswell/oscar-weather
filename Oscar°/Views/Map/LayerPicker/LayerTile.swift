import SwiftUI

/// One square layer tile, Apple-Maps-Kartenmodi-style: screenshot artwork with a
/// hairline rim, accent selection ring with a small gap, caption label below.
struct LayerTile: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let imageName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                artwork
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var artwork: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(decorative: imageName)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
            )
            .padding(3)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                }
            }
    }
}
