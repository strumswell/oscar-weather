import SwiftUI

struct InteractiveClimateRibbon: View {
    let stripes: [ClimateStripe]
    let sigma: Double
    let unit: ClimateTemperatureUnit
    var height: CGFloat = 96

    @State private var selectedIndex: Int?

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                callout(width: geometry.size.width)
            }
            .frame(height: 22)

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .topLeading) {
                    WarmingStripesRibbon(stripes: stripes, sigma: sigma, height: height, cornerRadius: 14)
                    if let index = selectedIndex, stripes.indices.contains(index) {
                        Rectangle()
                            .fill(.white)
                            .frame(width: 2, height: height)
                            .overlay(Rectangle().stroke(.black.opacity(0.35), lineWidth: 0.5))
                            .position(x: centerX(for: index, width: width), y: height / 2)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            selectedIndex = index(forX: value.location.x, width: width)
                        }
                        .onEnded { _ in selectedIndex = nil }
                )
            }
            .frame(height: height)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Verlauf der Tageshöchstwerte"))
        .accessibilityValue(accessibilityValueText)
        .accessibilityAdjustableAction { direction in
            guard !stripes.isEmpty else { return }
            let current = selectedIndex ?? stripes.count - 1
            switch direction {
            case .increment: selectedIndex = min(current + 1, stripes.count - 1)
            case .decrement: selectedIndex = max(current - 1, 0)
            @unknown default: break
            }
        }
    }

    /// VoiceOver reads the focused year and its high, defaulting to the most recent (today) before
    /// any scrub. Pairs with the adjustable action so swiping up/down steps through the years — the
    /// drag-to-scrub gesture itself isn't operable under VoiceOver.
    private var accessibilityValueText: Text {
        guard !stripes.isEmpty else { return Text(verbatim: "") }
        let index = min(max(selectedIndex ?? stripes.count - 1, 0), stripes.count - 1)
        let stripe = stripes[index]
        let temperature = Int(unit.value(fromCelsius: stripe.value).rounded())
        return Text(verbatim: "\(stripe.year), \(temperature)°")
    }

    /// Only shown while actively scrubbing; clears when the finger lifts.
    @ViewBuilder
    private func callout(width: CGFloat) -> some View {
        if let index = selectedIndex, stripes.indices.contains(index) {
            let stripe = stripes[index]
            let temperature = Int(unit.value(fromCelsius: stripe.value).rounded())
            let half: CGFloat = 52
            HStack(spacing: 6) {
                Circle()
                    .fill(ClimateStripeColor.color(anomaly: stripe.anomaly, sigma: sigma))
                    .frame(width: 8, height: 8)
                Text(verbatim: "\(stripe.year) · \(temperature)°")
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .cardBackground(in: Capsule())
            .overlay(Capsule().stroke(.secondary.opacity(0.15), lineWidth: 0.5))
            .position(
                x: min(max(centerX(for: index, width: width), half), max(width - half, half)),
                y: 11)
        }
    }

    private func centerX(for index: Int, width: CGFloat) -> CGFloat {
        guard !stripes.isEmpty else { return 0 }
        let stripeWidth = width / CGFloat(stripes.count)
        return (CGFloat(index) + 0.5) * stripeWidth
    }

    private func index(forX x: CGFloat, width: CGFloat) -> Int {
        guard !stripes.isEmpty, width > 0 else { return 0 }
        let stripeWidth = width / CGFloat(stripes.count)
        return min(max(Int(x / stripeWidth), 0), stripes.count - 1)
    }
}
