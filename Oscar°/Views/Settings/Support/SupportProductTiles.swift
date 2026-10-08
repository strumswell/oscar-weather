import StoreKit
import SwiftUI

/// A titled row of product tiles, each with a reel showing its current treat.
/// With `shuffle`, the header carries a trailing button that rerolls the reels.
struct SupportProductTiles: View {
    let title: LocalizedStringKey
    let ids: [String]
    let treats: [String: SupportTreat]
    var jackpot: SupportJackpot?
    var shuffle: (() -> Void)?
    var isShuffling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if let shuffle {
                    Button("Spin", systemImage: "shuffle", action: shuffle)
                        .font(.subheadline)
                        .disabled(isShuffling)
                }
            }
            if shuffle != nil {
                Text("Dreh so oft du willst, bis dir der Inhalt deines Care-Pakets an mich gefällt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ForEach(ids.enumerated(), id: \.element) { index, id in
                    ProductView(id: id)
                        .productViewStyle(SupportTileStyle(treat: treats[id] ?? .fallback, index: index, jackpot: jackpot))
                }
            }
        }
        .padding(.horizontal)
    }
}
