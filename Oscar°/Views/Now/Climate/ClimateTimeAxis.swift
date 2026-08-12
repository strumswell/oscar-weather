import SwiftUI

/// Decade labels under the ribbon, each placed at its true year position. The first year sits flush
/// left and "heute" flush right; interior labels are the 20-year marks that fit, dropping any within
/// 8 years of an endpoint so nothing collides.
struct ClimateTimeAxis: View {
    let firstYear: Int
    let todayYear: Int

    // Scale the row height with the caption2 metric so the labels don't clip at large Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var axisHeight: CGFloat = 13

    private struct Tick: Identifiable {
        let id: Int
        let isToday: Bool
        let fraction: Double
    }

    private var ticks: [Tick] {
        let span = Double(max(todayYear - firstYear, 1))
        var result = [Tick(id: firstYear, isToday: false, fraction: 0)]
        let start = ((firstYear + 8) / 20 + 1) * 20
        for year in stride(from: start, through: todayYear - 8, by: 20)
        where year > firstYear && year < todayYear {
            result.append(Tick(id: year, isToday: false, fraction: Double(year - firstYear) / span))
        }
        result.append(Tick(id: todayYear, isToday: true, fraction: 1))
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                ForEach(ticks) { tick in
                    label(for: tick)
                        .fixedSize()
                        // Center the label on its year, clamped so the end labels stay fully on-screen.
                        .alignmentGuide(.leading) { dimensions in
                            let center = tick.fraction * width
                            let leading = min(
                                max(center - dimensions.width / 2, 0),
                                max(width - dimensions.width, 0))
                            return -leading
                        }
                        .alignmentGuide(.top) { _ in 0 }
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(height: axisHeight)
    }

    @ViewBuilder
    private func label(for tick: Tick) -> some View {
        if tick.isToday {
            Text("heute")
        } else {
            Text(verbatim: "\(tick.id)")
        }
    }
}
