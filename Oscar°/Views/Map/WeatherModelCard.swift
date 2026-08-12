import SwiftUI

/// One model in the explainer: preview thumbnail, name, provider, a grid-size
/// capsule, and a one-liner on what the resolution means for the user.
struct WeatherModelCard: View {
    let name: String
    let provider: LocalizedStringKey
    let grid: LocalizedStringKey
    let imageName: String
    let summary: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: name)
                        .font(.subheadline.weight(.semibold))
                    Text(provider)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(grid)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.fill.secondary, in: Capsule())
            }
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
    }
}
