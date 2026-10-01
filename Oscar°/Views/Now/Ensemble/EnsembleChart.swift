import SwiftUI

/// One lens across all days: runs as nested bands (all faint, eight in ten
/// strong, median line), or for the sky each day's share of runs per weather.
struct EnsembleChart: View {
    let state: EnsembleState
    let lens: EnsembleLens

    @State private var readoutSize: CGSize = .zero

    static let axisHeight: CGFloat = 16

    var body: some View {
        let selected = state.selectedIndex
        let days = state.days

        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            Canvas { context, size in
                draw(context: &context, size: size, days: days, selected: selected)
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        state.select(atFraction: value.location.x / width)
                    }
            )
            .overlay(alignment: .topLeading) {
                EnsembleReadout(state: state, lens: lens)
                    .onGeometryChange(for: CGSize.self, of: { $0.size }) { readoutSize = $0 }
                    .offset(x: readoutX(width: width, count: days.count, selected: selected), y: 2)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lens.title)
        .accessibilityValue(Text(verbatim: state.accessibilityValue(for: lens)))
        .accessibilityAdjustableAction { direction in
            state.step(by: direction == .increment ? 1 : -1)
        }
    }

    private func readoutX(width: CGFloat, count: Int, selected: Int) -> CGFloat {
        let column = width / CGFloat(max(count, 1))
        let headX = (CGFloat(selected) + 0.5) * column
        let trailing = headX + column / 2 + 6
        guard trailing + readoutSize.width > width else { return trailing }
        return max(headX - column / 2 - 6 - readoutSize.width, 0)
    }

    private func draw(context: inout GraphicsContext, size: CGSize, days: [EnsembleDay], selected: Int) {
        guard !days.isEmpty else { return }
        let chartHeight = size.height - Self.axisHeight
        let column = size.width / CGFloat(days.count)

        let labelFont = Font.system(size: 10, weight: .medium)
        for label in state.axisLabels(columnWidth: column) {
            let text = context.resolve(
                Text(verbatim: label.text)
                    .font(labelFont)
                    .foregroundStyle(.white.opacity(label.index == selected ? 0.95 : 0.6))
            )
            let x = (CGFloat(label.index) + 0.5) * column
            context.fill(
                Path(CGRect(x: x - 0.375, y: 0, width: 0.75, height: chartHeight)),
                with: .color(.white.opacity(0.1))
            )
            let anchor: UnitPoint = label.index == 0 && column < 22 ? .leading : .center
            context.draw(text, at: CGPoint(x: anchor == .leading ? 0 : x, y: chartHeight + Self.axisHeight / 2 + 2), anchor: anchor)
        }

        if lens == .sky {
            drawSky(context: &context, days: days, selected: selected, column: column, chartHeight: chartHeight)
        } else {
            drawSpread(context: &context, days: days, selected: selected, size: size, column: column, chartHeight: chartHeight)
        }
    }

    private func drawSky(
        context: inout GraphicsContext,
        days: [EnsembleDay],
        selected: Int,
        column: CGFloat,
        chartHeight: CGFloat
    ) {
        let groundToSky: [EnsembleSky] = [.rain, .snow, .clouds, .sun]
        let barWidth = max(3, column * 0.62)
        let fullHeight = chartHeight - 6
        for (index, day) in days.enumerated() {
            let x = (CGFloat(index) + 0.5) * column - barWidth / 2
            var top = chartHeight
            for sky in groundToSky {
                let height = CGFloat(day.sky.share(of: sky)) * fullHeight
                guard height > 0 else { continue }
                let rect = CGRect(x: x, y: top - height, width: barWidth, height: max(height - 1, 0.5))
                context.fill(
                    Path(roundedRect: rect, cornerRadius: min(2, barWidth / 3)),
                    with: .color(sky.color.opacity(index == selected ? 1 : 0.55))
                )
                top -= height
            }
        }
        let outline = CGRect(
            x: (CGFloat(selected) + 0.5) * column - barWidth / 2 - 2.5,
            y: chartHeight - fullHeight - 2.5,
            width: barWidth + 5,
            height: fullHeight + 4
        )
        context.stroke(Path(roundedRect: outline, cornerRadius: 4), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
    }

    private func drawSpread(
        context: inout GraphicsContext,
        days: [EnsembleDay],
        selected: Int,
        size: CGSize,
        column: CGFloat,
        chartHeight: CGFloat
    ) {
        let spreads = days.map { state.spread(lens, of: $0) }
        let known = spreads.compactMap { $0 }
        guard let lowest = known.map(\.lowest).min(), let highest = known.map(\.highest).max(),
              let highestBand = known.map(\.high).max() else { return }
        let fromZero = lens == .precipitation || lens == .wind
        let bottom = fromZero ? 0 : lowest
        // A single soaked run would flatten every other day; its column runs off the top instead.
        let top = lens == .precipitation ? highestBand * 1.3 : highest
        let span = max(top - bottom, lens == .precipitation ? 2 : 4)
        let lower = fromZero ? 0 : bottom - span * 0.08
        let upper = bottom + span * 1.08
        func y(_ value: Double) -> CGFloat {
            chartHeight * (0.95 - 0.83 * CGFloat((value - lower) / (upper - lower)))
        }
        func x(_ index: Int) -> CGFloat { (CGFloat(index) + 0.5) * column }

        let step = Self.niceStep((upper - lower) / 3)
        let gridValues = stride(from: (lower / step).rounded(.up) * step, through: upper, by: step)
            .filter { y($0) > 12 && y($0) < chartHeight - 10 }
        for value in gridValues {
            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: y(value)))
            grid.addLine(to: CGPoint(x: size.width, y: y(value)))
            context.stroke(grid, with: .color(.white.opacity(0.1)), style: StrokeStyle(lineWidth: 0.75, dash: [2, 3]))
        }

        // Bands sit on a dark underlay so the series color stays saturated on a bright card wash.
        func layer(_ path: Path, opacity: Double, in target: inout GraphicsContext) {
            target.fill(path, with: .color(.black.opacity(0.15)))
            target.fill(path, with: .color(lens.color.opacity(opacity)))
        }

        if lens == .precipitation {
            let barWidth = max(3, column * 0.5)
            var bars = context
            bars.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: chartHeight)))
            for (index, spread) in spreads.enumerated() {
                guard let spread else { continue }
                let left = x(index) - barWidth / 2
                func bar(_ from: Double, _ to: Double) -> Path {
                    let rect = CGRect(x: left, y: y(to), width: barWidth, height: max(y(from) - y(to), 1))
                    return Path(roundedRect: rect, cornerRadius: min(2, barWidth / 3))
                }
                layer(bar(spread.lowest, spread.highest), opacity: 0.3, in: &bars)
                layer(bar(spread.low, spread.high), opacity: 0.75, in: &bars)
                let tick = CGRect(x: left - 1, y: y(spread.median) - 1.75, width: barWidth + 2, height: 3.5)
                bars.fill(Path(roundedRect: tick, cornerRadius: 1.75), with: .color(.white))
                bars.fill(Path(roundedRect: tick.insetBy(dx: 1, dy: 1), cornerRadius: 0.75), with: .color(lens.color))
            }
        } else {
            func band(_ bottom: KeyPath<EnsembleSpread, Double>, _ top: KeyPath<EnsembleSpread, Double>) -> Path {
                let points = spreads.enumerated().compactMap { index, spread in spread.map { (index, $0) } }
                var path = Path()
                path.addMonotoneCurve(through: points.map { CGPoint(x: x($0.0), y: y($0.1[keyPath: top])) })
                path.addMonotoneCurve(through: points.reversed().map { CGPoint(x: x($0.0), y: y($0.1[keyPath: bottom])) })
                path.closeSubpath()
                return path
            }
            layer(band(\.lowest, \.highest), opacity: 0.3, in: &context)
            layer(band(\.low, \.high), opacity: 0.75, in: &context)
            var median = Path()
            median.addMonotoneCurve(through: spreads.enumerated().compactMap { index, spread in
                spread.map { CGPoint(x: x(index), y: y($0.median)) }
            })
            context.stroke(median, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            context.stroke(median, with: .color(lens.color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }

        var labelContext = context
        labelContext.addFilter(.shadow(color: .black.opacity(0.45), radius: 1.5))
        var taken: [CGRect] = []
        for value in gridValues {
            let label = labelContext.resolve(
                Text(verbatim: state.formatted(value, for: lens))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            )
            let labelSize = label.measure(in: CGSize(width: 200, height: 20))
            taken.append(CGRect(x: size.width - 2 - labelSize.width, y: y(value) - 2 - labelSize.height,
                                width: labelSize.width, height: labelSize.height))
            labelContext.draw(label, at: CGPoint(x: size.width - 2, y: y(value) - 2), anchor: .bottomTrailing)
        }

        let every = max(1, Int((26 / column).rounded(.up)))
        for index in stride(from: 0, to: spreads.count, by: every) where index != selected {
            guard let spread = spreads[index], lens != .precipitation || spread.median >= 0.1 else { continue }
            let label = labelContext.resolve(
                Text(verbatim: state.number(spread.median, for: lens) + (lens == .high || lens == .low ? "°" : ""))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            let labelSize = label.measure(in: CGSize(width: 200, height: 20))
            let above = y(spread.median) - 5 - labelSize.height
            let top = above > 2 ? above : min(y(spread.median) + 5, chartHeight - labelSize.height)
            let rect = CGRect(
                x: min(max(x(index) - labelSize.width / 2, 0), size.width - labelSize.width),
                y: top,
                width: labelSize.width,
                height: labelSize.height
            )
            guard !taken.contains(where: { $0.insetBy(dx: -2, dy: -1).intersects(rect) }) else { continue }
            taken.append(rect)
            labelContext.draw(label, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }

        let headX = x(selected)
        context.fill(
            Path(CGRect(x: headX - 0.75, y: 0, width: 1.5, height: chartHeight)),
            with: .color(.white.opacity(0.95))
        )
        if let spread = spreads[selected] {
            let dot = Path(ellipseIn: CGRect(x: headX - 4, y: y(spread.median) - 4, width: 8, height: 8))
            context.fill(dot, with: .color(.white))
            context.stroke(dot, with: .color(lens.color), lineWidth: 2)
        }
    }

    private static func niceStep(_ raw: Double) -> Double {
        let magnitude = pow(10, floor(log10(max(raw, 0.0001))))
        let normalized = raw / magnitude
        if normalized < 1.5 { return magnitude }
        if normalized < 3.5 { return 2 * magnitude }
        if normalized < 7.5 { return 5 * magnitude }
        return 10 * magnitude
    }
}

/// The selected day's numbers beside the playhead; each row's swatch
/// matches its layer in the chart, so the box is the legend too.
private struct EnsembleReadout: View {
    let state: EnsembleState
    let lens: EnsembleLens

    var body: some View {
        if let day = state.selectedDay {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: state.shortDateLabel(day))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.bottom, 1)

                if lens == .sky {
                    ForEach(EnsembleSky.allCases.reversed().filter { day.sky.share(of: $0) > 0 }, id: \.self) { sky in
                        row(swatch: Circle().fill(sky.color), label: sky.title,
                            value: day.sky.share(of: sky).formatted(.percent.precision(.fractionLength(0))))
                    }
                } else if let spread = state.spread(lens, of: day) {
                    row(swatch: Capsule().fill(lens.color).stroke(.white, lineWidth: 1).frame(height: 4), label: String(localized: "Median"),
                        value: state.formatted(spread.median, for: lens))
                    row(swatch: RoundedRectangle(cornerRadius: 2).fill(lens.color.opacity(0.85)),
                        label: String(localized: "8 von 10"),
                        value: state.range(spread.low, spread.high, for: lens))
                    row(swatch: RoundedRectangle(cornerRadius: 2).fill(lens.color.opacity(0.4)),
                        label: String(localized: "Alle"),
                        value: state.range(spread.lowest, spread.highest, for: lens))
                }
            }
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(8)
            .background(.ultraThinMaterial.opacity(0.9))
            .clipShape(.rect(cornerRadius: 8))
            .shadow(radius: 4)
        }
    }

    private func row(swatch: some View, label: String, value: String) -> some View {
        HStack(spacing: 5) {
            swatch
                .frame(width: 8, height: 8)
            Text(verbatim: label)
                .foregroundStyle(.white.opacity(0.75))
            Text(verbatim: value)
                .foregroundStyle(.white)
        }
    }
}

extension Path {
    /// Monotone cubic (Fritsch–Carlson) through points ordered along x: smooth
    /// like the hourly lines, but never overshoots past the data between days.
    mutating func addMonotoneCurve(through points: [CGPoint]) {
        guard let first = points.first else { return }
        if isEmpty { move(to: first) } else { addLine(to: first) }
        let count = points.count
        guard count > 1 else { return }
        let slopes: [CGFloat] = (0..<count - 1).map { (points[$0 + 1].y - points[$0].y) / (points[$0 + 1].x - points[$0].x) }
        var tangents: [CGFloat] = [slopes[0]] + (1..<count - 1).map { slopes[$0 - 1] * slopes[$0] <= 0 ? 0 : (slopes[$0 - 1] + slopes[$0]) / 2 } + [slopes[count - 2]]
        for i in 0..<count - 1 {
            guard slopes[i] != 0 else {
                tangents[i] = 0
                tangents[i + 1] = 0
                continue
            }
            let a = tangents[i] / slopes[i], b = tangents[i + 1] / slopes[i]
            let length = a * a + b * b
            if length > 9 {
                let scale = 3 / length.squareRoot()
                tangents[i] = scale * a * slopes[i]
                tangents[i + 1] = scale * b * slopes[i]
            }
        }
        for i in 0..<count - 1 {
            let third = (points[i + 1].x - points[i].x) / 3
            addCurve(
                to: points[i + 1],
                control1: CGPoint(x: points[i].x + third, y: points[i].y + tangents[i] * third),
                control2: CGPoint(x: points[i + 1].x - third, y: points[i + 1].y - tangents[i + 1] * third)
            )
        }
    }
}
