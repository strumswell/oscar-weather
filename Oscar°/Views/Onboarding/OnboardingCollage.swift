//
//  OnboardingCollage.swift
//  Oscar°
//

import SwiftUI

/// The feature-tour backdrop: three endless columns of real app components
/// with staged data, tilted 20° so they drift from bottom-right to top-left.
/// Each column loops render-server-side (one repeatForever offset animation),
/// so no per-frame body work happens.

/// Cheap stand-in for the cards' live material: dozens of copies drift over
/// the animated sky, and each `.thinMaterial` would re-blur its backdrop
/// every frame. A translucent fill composites with plain alpha instead.
let collageCardFill = AnyShapeStyle(Color(.systemBackground).opacity(0.78))

struct OnboardingCollage: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // Only the hero window band is ever visible — everything below it
            // sits under the opaque stage canvas, so never composite it.
            let bandHeight = size.height * OnboardingStage.heroFraction

            HStack(alignment: .top, spacing: 14) {
                OnboardingMarqueeColumn(speed: 24, initialOffset: -60) {
                    columnOne
                }
                OnboardingMarqueeColumn(speed: 36, initialOffset: -220) {
                    columnTwo
                }
                OnboardingMarqueeColumn(speed: 29, initialOffset: -130) {
                    columnThree
                }
            }
            .frame(width: 660)
            .rotationEffect(.degrees(-20))
            .position(x: size.width / 2, y: bandHeight / 2)
            .frame(width: size.width, height: bandHeight, alignment: .top)
            // Clip the tilted overflow to the band so the offscreen copies of
            // each looping column are never composited — only what's visible pays.
            .clipped()
        }
        .environment(\.cardBackgroundStyle, collageCardFill)
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ViewBuilder private var columnOne: some View {
        HStack(spacing: 12) {
            HourlyForecastCard(item: OnboardingSampleData.hourlyItems[0])
            HourlyForecastCard(item: OnboardingSampleData.hourlyItems[1])
        }
        CollageRadarCard(assetName: "layer-gfs-temp")
        HourlySunEventCard(item: OnboardingSampleData.sunset)
        CollageIconRow(assetNames: OnboardingSampleData.appIconPreviews)
        AQIGaugeCard(metric: OnboardingSampleData.gauges[0])
        CollageRadarCard()
        HStack(spacing: 12) {
            HourlyForecastCard(item: OnboardingSampleData.hourlyItems[2])
            HourlyForecastCard(item: OnboardingSampleData.hourlyItems[3])
        }
        CollageClimateCard()
        CollageRadarCard(assetName: "layer-icon-wind")
        CollageDailyCard()
    }

    @ViewBuilder private var columnTwo: some View {
        CollageDailyCard()
        HStack(spacing: 12) {
            AQIGaugeCard(metric: OnboardingSampleData.gauges[1])
            AQIGaugeCard(metric: OnboardingSampleData.gauges[2])
        }
        CollageRadarCard(assetName: "layer-gfs-wind")
        CollageEnsembleCard()
        HourlySunEventCard(item: OnboardingSampleData.sunrise)
        CollageRadarCard(assetName: "layer-icon-pressure")
        CollageIconRow(assetNames: OnboardingSampleData.appIconPreviewsAlternate)
        HStack(spacing: 12) {
            HourlyForecastCard(item: OnboardingSampleData.hourlyItems[0])
            HourlyForecastCard(item: OnboardingSampleData.hourlyItems[4])
        }
    }

    @ViewBuilder private var columnThree: some View {
        CollageRadarCard(assetName: "layer-radar-europe")
        HStack(spacing: 12) {
            HourlyForecastCard(item: OnboardingSampleData.hourlyItems[4])
            HourlyForecastCard(item: OnboardingSampleData.hourlyItems[5])
        }
        CollageClimateCard()
        CollageRadarCard(assetName: "layer-icon-precip")
        AQIGaugeCard(metric: OnboardingSampleData.gauges[0])
        CollageDailyCard()
        CollageRadarCard(assetName: "layer-radar-usa")
        HourlySunEventCard(item: OnboardingSampleData.sunset)
        CollageIconRow(assetNames: OnboardingSampleData.appIconPreviews)
    }
}

/// Loops its content vertically at a constant speed. The content is laid out
/// `copies` times up front (so every card exists before it scrolls into view —
/// nothing pops in), and a single linear repeatForever offset advances by exactly
/// one copy, so the seam is invisible. Enough copies are stacked that the tilted
/// viewport stays covered throughout the cycle. The offset is a pure transform,
/// so scrolling is GPU-only — no per-frame body work.
private struct OnboardingMarqueeColumn<Content: View>: View {
    let speed: Double
    var initialOffset: CGFloat = 0
    var copies: Int = 4
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stackHeight: CGFloat = 0
    @State private var rolling = false

    private let spacing: CGFloat = 14

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<copies, id: \.self) { _ in
                VStack(spacing: spacing) { content }
            }
        }
        .frame(width: 200)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { total in
            stackHeight = total
        }
        .offset(y: initialOffset - (rolling ? copyStride : 0))
        .onChange(of: stackHeight) { _, _ in restart() }
        .onChange(of: reduceMotion) { _, _ in restart() }
    }

    /// The advance for one loop: a single copy's height plus its trailing gap.
    private var copyStride: CGFloat {
        guard copies > 0 else { return 0 }
        return (stackHeight + spacing) / CGFloat(copies)
    }

    private func restart() {
        guard stackHeight > 0, !reduceMotion else {
            rolling = false
            return
        }
        rolling = false
        withAnimation(.linear(duration: copyStride / speed).repeatForever(autoreverses: false)) {
            rolling = true
        }
    }
}
