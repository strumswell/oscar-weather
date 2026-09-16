import StoreKit
import SwiftUI

/// A titled row of product tiles; the heart grows with the tier.
struct SupportProductTiles: View {
    let title: LocalizedStringKey
    let ids: [String]
    let showsName: Bool
    let pulse: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            HStack(spacing: 12) {
                ForEach(ids.enumerated(), id: \.element) { index, id in
                    ProductView(id: id)
                        .productViewStyle(SupportTileStyle(heartSize: 18 + 5 * Double(index), showsName: showsName, pulse: pulse))
                }
            }
        }
        .padding(.horizontal)
    }
}
