// Radar-palette rain bars on a fixed log scale, shared by widgets, Siri, watch and onboarding.
import SwiftUI
import WidgetKit

enum RainIntensity {
    static let ceiling = 20.0

    static var isInch: Bool { SettingService.resolvedUnits.precipitation == .inch }
    static var unit: String { SettingService.resolvedUnits.precipitation.rateSymbol }

    static var gridlines: [Double] { isInch ? [1.27, 5.08] : [1, 5] }

    static func fraction(_ mmPerHour: Double, ceiling: Double = ceiling) -> Double {
        guard mmPerHour > 0 else { return 0 }
        let knee = 0.1
        return min(1, log1p(mmPerHour / knee) / log1p(ceiling / knee))
    }

    static func format(_ mmPerHour: Double) -> String {
        if isInch {
            return SettingService.resolvedUnits.precipitationNumber(mmPerHour)
        }
        return mmPerHour.formatted(.number.precision(.fractionLength(mmPerHour < 10 ? 1 : 0)))
    }

    static func scaleLabel(_ mmPerHour: Double) -> String {
        let value = isInch ? mmPerHour / 25.4 : mmPerHour
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func color(_ mmPerHour: Double) -> Color {
        let stops = ServerColormapStops.radar
        let dbz: Double = 10 * log10(200 * pow(max(mmPerHour, 0.01), 1.6))
        guard let upper = stops.firstIndex(where: { $0.dbz >= dbz }) else {
            return Color(hex: stops[stops.count - 1].hex)
        }
        guard upper > 0 else { return Color(hex: stops[0].hex) }
        let low = stops[upper - 1], high = stops[upper]
        let progress: Double = (dbz - low.dbz) / (high.dbz - low.dbz)
        return Color(hex: low.hex).mix(with: Color(hex: high.hex), by: progress)
    }
}

struct RainBarsChart: View {
    enum Axis {
        case none
        case span
        case times(start: Date, timeZone: TimeZone = .current)
    }

    let values: [Double]
    let height: CGFloat
    var axis: Axis = .span
    var ceiling = RainIntensity.ceiling
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isFullColor: Bool { renderingMode == .fullColor }

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<RainNowcastSummary.maxBars, id: \.self) { index in
                    let value = values.indices.contains(index) ? values[index] : nil
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(fill(value))
                        .frame(height: barHeight(value ?? 0))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: height, alignment: .bottom)
            .background(alignment: .bottom) {
                if isFullColor {
                    gridlines
                }
            }
            axisRow
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Regenverlauf"))
    }

    private func barHeight(_ value: Double) -> CGFloat {
        value > 0 ? max(3, height * RainIntensity.fraction(value, ceiling: ceiling)) : 2
    }

    private func fill(_ value: Double?) -> Color {
        guard let value else { return .clear }
        if value <= 0 {
            return isFullColor ? .white.opacity(0.2) : .secondary.opacity(0.35)
        }
        return isFullColor ? RainIntensity.color(value) : .primary
    }

    private var gridlines: some View {
        ZStack(alignment: .bottom) {
            ForEach(RainIntensity.gridlines.filter { $0 < ceiling }, id: \.self) { value in
                HorizontalLine()
                    .stroke(.white.opacity(0.28), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    .frame(height: 0.5)
                    .offset(y: -height * RainIntensity.fraction(value, ceiling: ceiling))
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    @ViewBuilder
    private var axisRow: some View {
        switch axis {
        case .none:
            EmptyView()
        case .span:
            axisLabels([String(localized: "+\(RainNowcastSummary.maxBars * 5) min")])
        case .times(let start, let timeZone):
            axisLabels([30, 60, 90].map { SettingService.formattedTime(start.addingTimeInterval(Double($0) * 60), timeZone: timeZone) })
        }
    }

    private func axisLabels(_ labels: [String]) -> some View {
        HStack(spacing: 0) {
            Text("Jetzt")
            ForEach(labels, id: \.self) { label in
                Spacer(minLength: 0)
                Text(verbatim: label)
            }
        }
        .font(.system(size: 9, weight: .medium))
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(isFullColor ? Color.white.opacity(0.6) : Color.secondary)
    }
}

private struct HorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
