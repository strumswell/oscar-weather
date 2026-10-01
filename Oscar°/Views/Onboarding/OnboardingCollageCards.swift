import SwiftUI

/// Compact five-day block built from the real temperature-range bars.
struct CollageDailyCard: View {
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
struct CollageRadarCard: View {
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
struct CollageClimateCard: View {
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

/// Ensemble temperature card. One Canvas: the collage stamps many of these,
/// and a static bitmap of bands + mean lines composites cheaply.
struct CollageEnsembleCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("7-Tage-Ensemble")
                .font(.footnote.weight(.semibold))
            CollageEnsembleChart(samples: OnboardingSampleData.ensembleSamples)
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
    let samples: [OnboardingSampleData.EnsembleSample]

    var body: some View {
        Canvas { context, size in
            guard samples.count > 1 else { return }

            let upper = (samples.map { $0.high + $0.spread }.max() ?? 30) + 1.5
            let lower = (samples.map { $0.low - $0.spread }.min() ?? 10) - 1.5
            let span = max(upper - lower, 1)

            func point(_ index: Int, _ value: Double) -> CGPoint {
                CGPoint(
                    x: size.width * CGFloat(index) / CGFloat(samples.count - 1),
                    y: size.height * (1 - CGFloat((value - lower) / span))
                )
            }

            func band(_ bottom: (OnboardingSampleData.EnsembleSample) -> Double,
                      _ top: (OnboardingSampleData.EnsembleSample) -> Double,
                      _ color: Color) {
                var path = Path()
                path.addLines(samples.indices.map { point($0, top(samples[$0])) })
                for index in samples.indices.reversed() {
                    path.addLine(to: point(index, bottom(samples[index])))
                }
                path.closeSubpath()
                context.fill(path, with: .color(color.opacity(0.16)))
            }

            func line(_ value: (OnboardingSampleData.EnsembleSample) -> Double, _ color: Color) {
                var path = Path()
                path.addLines(samples.indices.map { point($0, value(samples[$0])) })
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }

            band({ $0.high - $0.spread * 0.9 }, { $0.high + $0.spread }, .red)
            band({ $0.low - $0.spread }, { $0.low + $0.spread * 0.8 }, .blue)
            line(\.high, .red)
            line(\.low, .blue)
        }
    }
}

/// A row of alternative app icons from the icon picker's preview assets.
struct CollageIconRow: View {
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
