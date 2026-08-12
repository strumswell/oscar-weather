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

/// Ensemble temperature card. Drawn with a single Canvas rather than the live
/// Swift Charts view: the collage stamps many of these, and a static bitmap of
/// bands + mean lines composites far cheaper than a full chart with axes,
/// gestures, and scroll state — matching its red/blue look.
struct CollageEnsembleCard: View {
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
