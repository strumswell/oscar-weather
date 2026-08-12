import SwiftUI

/// "kühler ▭▭▭ wärmer" — a small blue→red gradient key for the stripe colors.
struct ClimateLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("kühler als normal")
            Capsule()
                .fill(
                    LinearGradient(
                        colors: ClimateStripeColor.legendGradient,
                        startPoint: .leading, endPoint: .trailing)
                )
                .frame(height: 6)
            Text("wärmer als normal")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement()
        .accessibilityLabel(Text("Farbskala von kühler als normal (blau) bis wärmer als normal (rot)."))
    }
}
