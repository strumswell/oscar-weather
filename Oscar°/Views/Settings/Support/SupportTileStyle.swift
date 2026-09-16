import StoreKit
import SwiftUI

/// One product as a tappable tile: a heart sized by tier, the price, and the
/// name where it carries the period (monthly/yearly).
struct SupportTileStyle: ProductViewStyle {
    let heartSize: Double
    let showsName: Bool
    let pulse: Int

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.purchase()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: heartSize))
                    .foregroundStyle(.pink)
                    .symbolEffect(.bounce, value: pulse)
                    .frame(height: 34)
                    .accessibilityHidden(true)

                if let product = configuration.product {
                    if showsName {
                        Text(product.displayName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
            .frame(maxWidth: .infinity, minHeight: 92)
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
