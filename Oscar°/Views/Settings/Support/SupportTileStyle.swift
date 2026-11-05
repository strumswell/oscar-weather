import StoreKit
import SwiftUI

struct SupportTileStyle: ProductViewStyle {
    let treat: SupportTreat
    let index: Int
    let jackpot: SupportJackpot?
    let isPending: Bool

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.purchase()
        } label: {
            VStack(spacing: 6) {
                TreatReel(treat: treat, index: index, jackpot: jackpot)
                    .environment(\.locale, .current)

                if isPending {
                    ProgressView()
                } else if let product = configuration.product {
                    Text(product.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Self.price(of: product)
                        .font(.headline)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
        .disabled(configuration.product == nil || isPending)
        .accessibilityLabel(configuration.product.map { Text("\($0.displayName), \(Self.price(of: $0))") } ?? Text(verbatim: "–"))
    }

    static func price(of product: Product) -> Text {
        switch product.subscription?.subscriptionPeriod.unit {
        case .day: Text("\(product.displayPrice) / Tag")
        case .week: Text("\(product.displayPrice) / Woche")
        case .month: Text("\(product.displayPrice) / Monat")
        case .year: Text("\(product.displayPrice) / Jahr")
        default: Text(product.displayPrice)
        }
    }
}
