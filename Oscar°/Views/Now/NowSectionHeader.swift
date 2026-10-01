import SwiftUI

/// A Now section's title with a quiet "Mehr" link to its detail page, so the
/// way in doesn't depend on guessing that the card is tappable.
struct NowSectionHeader<Title: View>: View {
    var showMore: (() -> Void)?
    @ViewBuilder let title: Title

    var body: some View {
        HStack {
            title
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if let showMore {
                Button(action: showMore) {
                    HStack(spacing: 2) {
                        Text("Mehr")
                        Image(systemName: "chevron.forward")
                            .imageScale(.small)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle().inset(by: -10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}
