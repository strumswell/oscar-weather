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
private let collageCardFill = AnyShapeStyle(Color(.systemBackground).opacity(0.78))

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

/// Compact five-day block built from the real temperature-range bars.
private struct CollageDailyCard: View {
    var body: some View {
        VStack(spacing: 14) {
            ForEach(OnboardingSampleData.dailyRows) { row in
                HStack(spacing: 8) {
                    Text(row.weekday)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .frame(width: 42, alignment: .leading)
                    Image(row.iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    Text(verbatim: "\(Int(row.low))°")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TemperatureRangeView(
                        low: row.low,
                        high: row.high,
                        focusLow: nil,
                        focusHigh: nil,
                        minTemp: OnboardingSampleData.dailyTemperatureBounds.min,
                        maxTemp: OnboardingSampleData.dailyTemperatureBounds.max,
                        unit: "°C"
                    )
                    .frame(height: 5)
                    Text(verbatim: "\(Int(row.high))°")
                        .font(.footnote)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(collageCardFill)
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.secondary.opacity(0.075), lineWidth: 1)
        }
    }
}

/// Static radar layer preview in a map-style card.
private struct CollageRadarCard: View {
    var assetName = "layer-radar-germany"

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(width: 200, height: 150)
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.secondary.opacity(0.15), lineWidth: 1)
            }
    }
}

/// Warming stripes with a small title, like the Klima section's ribbon.
private struct CollageClimateCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dieser Tag seit 1940")
                .font(.footnote.weight(.semibold))
            WarmingStripesRibbon(
                stripes: OnboardingSampleData.climateStripes,
                sigma: 1.0,
                height: 40
            )
        }
        .padding(14)
        .background(collageCardFill)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.secondary.opacity(0.08), lineWidth: 1)
        }
    }
}

/// Ensemble temperature card. Drawn with a single Canvas rather than the live
/// Swift Charts view: the collage stamps many of these, and a static bitmap of
/// bands + mean lines composites far cheaper than a full chart with axes,
/// gestures, and scroll state — matching its red/blue look.
private struct CollageEnsembleCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("7-Tage-Ensemble")
                .font(.footnote.weight(.semibold))
            CollageEnsembleChart(points: OnboardingSampleData.ensemblePoints)
                .frame(height: 130)
        }
        .padding(14)
        .background(collageCardFill)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.secondary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct CollageEnsembleChart: View {
    let points: [DailyEnsembleDayPoint]

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }

            let highs = points.compactMap(\.temperatureMaxMemberHigh)
            let lows = points.compactMap(\.temperatureMinMemberLow)
            let upper = (highs.max() ?? 30) + 1.5
            let lower = (lows.min() ?? 10) - 1.5
            let span = max(upper - lower, 1)

            func point(_ index: Int, _ value: Double) -> CGPoint {
                let x = size.width * CGFloat(index) / CGFloat(points.count - 1)
                let y = size.height * (1 - CGFloat((value - lower) / span))
                return CGPoint(x: x, y: y)
            }

            func band(_ low: KeyPath<DailyEnsembleDayPoint, Double?>,
                      _ high: KeyPath<DailyEnsembleDayPoint, Double?>,
                      _ color: Color) {
                var path = Path()
                var started = false
                for (index, item) in points.enumerated() {
                    guard let value = item[keyPath: high] else { continue }
                    let p = point(index, value)
                    if started { path.addLine(to: p) } else { path.move(to: p); started = true }
                }
                for (index, item) in points.enumerated().reversed() {
                    guard let value = item[keyPath: low] else { continue }
                    path.addLine(to: point(index, value))
                }
                path.closeSubpath()
                context.fill(path, with: .color(color.opacity(0.16)))
            }

            func line(_ keyPath: KeyPath<DailyEnsembleDayPoint, Double?>, _ color: Color) {
                var path = Path()
                var started = false
                for (index, item) in points.enumerated() {
                    guard let value = item[keyPath: keyPath] else { continue }
                    let p = point(index, value)
                    if started { path.addLine(to: p) } else { path.move(to: p); started = true }
                }
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }

            band(\.temperatureMaxMemberLow, \.temperatureMaxMemberHigh, .red)
            band(\.temperatureMinMemberLow, \.temperatureMinMemberHigh, .blue)
            line(\.temperatureMax, .red)
            line(\.temperatureMin, .blue)
        }
    }
}

/// A row of alternative app icons from the icon picker's preview assets.
private struct CollageIconRow: View {
    let assetNames: [String]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(assetNames, id: \.self) { name in
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(collageCardFill)
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.secondary.opacity(0.075), lineWidth: 1)
        }
    }
}
