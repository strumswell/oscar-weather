import SwiftUI

struct WarmingStripesRibbon: View {
    let stripes: [ClimateStripe]
    let sigma: Double
    var height: CGFloat = 54
    var cornerRadius: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            guard !stripes.isEmpty else { return }
            let stripeWidth = size.width / CGFloat(stripes.count)
            for (index, stripe) in stripes.enumerated() {
                let x = CGFloat(index) * stripeWidth
                // Overdraw a hair so adjacent fills don't leave hairline seams.
                let rect = CGRect(x: x, y: 0, width: stripeWidth + 0.75, height: size.height)
                context.fill(
                    Path(rect),
                    with: .color(ClimateStripeColor.color(anomaly: stripe.anomaly, sigma: sigma)))
            }
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(.secondary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
