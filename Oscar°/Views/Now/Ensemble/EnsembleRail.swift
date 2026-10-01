import SwiftUI

/// The day picker under the deck: the highs' eight-in-ten band (its widening
/// is the forecast losing certainty), rain ticks, and the selected day's box.
struct EnsembleRail: View {
    let state: EnsembleState

    static let chartHeight: CGFloat = 40
    private static let labelHeight: CGFloat = 13

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            ZStack {
                RailSeries(state: state)
                RailSelection(state: state)
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        state.select(atFraction: value.location.x / width)
                    }
            )
        }
        .frame(height: Self.chartHeight + Self.labelHeight)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .cardBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardBorder(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Übersicht"))
        .accessibilityValue(Text(verbatim: state.selectedDay.map(state.shortDateLabel) ?? ""))
        .accessibilityAdjustableAction { direction in
            state.step(by: direction == .increment ? 1 : -1)
        }
    }
}

private struct RailSeries: View {
    let state: EnsembleState

    var body: some View {
        let days = state.days
        Canvas { context, size in
            draw(context: &context, size: size, days: days)
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize, days: [EnsembleDay]) {
        guard !days.isEmpty else { return }
        let height = EnsembleRail.chartHeight
        let column = size.width / CGFloat(days.count)
        func x(_ index: Int) -> CGFloat { (CGFloat(index) + 0.5) * column }

        let barWidth = max(2, column * 0.45)
        for (index, day) in days.enumerated() {
            let share = day.sky.share(of: .rain) + day.sky.share(of: .snow)
            guard share > 0 else { continue }
            let barHeight = max(1.5, CGFloat(share) * height * 0.45)
            context.fill(
                Path(CGRect(x: x(index) - barWidth / 2, y: height - barHeight, width: barWidth, height: barHeight)),
                with: .color(.hourlyRain.opacity(0.9))
            )
        }

        let highs = days.enumerated().compactMap { index, day in day.high.map { (index, $0) } }
        if let lowest = highs.map(\.1.low).min(), let highest = highs.map(\.1.high).max() {
            let span = max(highest - lowest, 1)
            func y(_ value: Double) -> CGFloat { height * (0.8 - 0.62 * CGFloat((value - lowest) / span)) }
            var band = Path()
            band.addLines(
                highs.map { CGPoint(x: x($0.0), y: y($0.1.high)) }
                    + highs.reversed().map { CGPoint(x: x($0.0), y: y($0.1.low)) }
            )
            band.closeSubpath()
            context.fill(band, with: .color(.white.opacity(0.28)))
            var median = Path()
            median.addLines(highs.map { CGPoint(x: x($0.0), y: y($0.1.median)) })
            context.stroke(median, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
        }

        let labelFont = Font.system(size: 9.5, weight: .medium)
        for label in state.axisLabels(columnWidth: column) {
            let text = context.resolve(
                Text(verbatim: label.text).font(labelFont).foregroundStyle(.white.opacity(0.7))
            )
            let anchor: UnitPoint = label.index == 0 && column < 22 ? .topLeading : .top
            context.draw(text, at: CGPoint(x: anchor == .topLeading ? 0 : x(label.index), y: height + 2), anchor: anchor)
        }
    }
}

private struct RailSelection: View {
    let state: EnsembleState

    var body: some View {
        let selected = state.selectedIndex
        let count = state.days.count
        Canvas { context, size in
            guard count > 0 else { return }
            let column = size.width / CGFloat(count)
            let width = max(column, 8)
            let rect = CGRect(
                x: (CGFloat(selected) + 0.5) * column - width / 2,
                y: 0.75,
                width: width,
                height: EnsembleRail.chartHeight - 1.5
            )
            let box = Path(roundedRect: rect, cornerRadius: min(6, width / 3))
            context.fill(box, with: .color(.white.opacity(0.1)))
            context.stroke(box, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        }
    }
}
