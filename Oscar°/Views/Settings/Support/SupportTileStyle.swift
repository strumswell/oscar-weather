import StoreKit
import SwiftUI

/// One product as a tappable tile: a slot reel showing what the tier would
/// buy, then the price.
struct SupportTileStyle: ProductViewStyle {
    let treat: SupportTreat
    let index: Int
    let jackpot: SupportJackpot?

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.purchase()
        } label: {
            VStack(spacing: 6) {
                TreatReel(treat: treat, index: index, jackpot: jackpot)

                if let product = configuration.product {
                    Text(product.displayPrice)
                        .font(.headline)
                        .monospacedDigit()
                } else if case .loading = configuration.state {
                    ProgressView()
                } else {
                    Text(verbatim: "–")
                        .font(.headline)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 18))
            .overlay(alignment: .topTrailing) {
                if configuration.hasCurrentEntitlement {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .padding(8)
                        .accessibilityLabel("Aktiv")
                }
            }
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(configuration.product == nil)
    }
}
