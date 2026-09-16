import SwiftUI

/// The focused mini chart inside a chapter card, scoped to the chapter's
/// hours. Canvas like the strip.
struct HourlyChapterChart: View {
    let model: HourlyTimelineModel
    let chapter: ChapterEngine.Chapter

    private static let axisHeight: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            draw(context: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    private var chartRange: ClosedRange<Double> {
        switch chapter.kind {
        case .precipitation, .wind:
            var lower = chapter.range.lowerBound - 3_600
            var upper = chapter.range.upperBound + 3_600
            let missing = 5 * 3_600 - (upper - lower)
            if missing > 0 {
                lower -= missing / 2
                upper += missing / 2
            }
            return lower...upper
        default:
            return chapter.range
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        if chapter.kind == .radar {
            drawRadar(context: &context, size: size)
            return
        }
        guard let indices = model.hourIndices(
            from: chartRange.lowerBound, until: chartRange.upperBound
        ), indices.count > 1 else { return }
        let width = size.width
        let chartHeight = size.height - Self.axisHeight
        let slot = width / CGFloat(indices.count)

        func x(_ position: Int) -> CGFloat {
            (CGFloat(position) + 0.5) * slot
        }
        func series(_ values: [Double]) -> [Double] {
            indices.map { $0 < values.count ? values[$0] : 0 }
        }

        context.fill(
            Path(CGRect(x: 0, y: chartHeight - 0.5, width: width, height: 1)),
            with: .color(.white.opacity(0.15))
        )

        switch chapter.kind {
        case .precipitation:
            let rates = series(model.precipitation)
            let snow = series(model.snowfall)
            let maxRate = max(rates.max() ?? 0, 0.5)
            let barBand = chartHeight * 0.58
            drawBars(
                context: &context, rates: rates, snow: snow,
                maxValue: maxRate, band: barBand, chartHeight: chartHeight, slot: slot, x: x
            )
            if rates.count <= 12 {
                for (position, rate) in rates.enumerated() where rate > 0 {
                    drawLabel(
                        context: &context,
                        text: rate.formatted(.number.precision(.fractionLength(1))),
                        at: CGPoint(
                            x: x(position),
                            y: max(6, chartHeight - max(3, barBand * CGFloat(rate / maxRate)) - 8)
                        ),
                        width: width
                    )
                }
            }
            let gusts = series(model.windgusts)
            if let maxGust = gusts.max(), maxGust > 0 {
                let gustTop = max(maxGust, 1) * 1.1
                let gustBand = chartHeight * 0.42
                let gustOffset = chartHeight * 0.34
                drawLine(
                    context: &context, values: gusts, color: .teal, width: 2,
                    band: gustBand, offset: gustOffset, chartHeight: chartHeight, x: x,
                    maxValue: gustTop
                )
                let gustStep = gusts.count <= 8 ? 1 : gusts.count <= 16 ? 2 : 3
                for position in stride(from: 0, to: gusts.count, by: gustStep) {
                    drawLabel(
                        context: &context,
                        text: "\(Int(gusts[position].rounded()))",
                        at: CGPoint(
                            x: x(position),
                            y: max(6, chartHeight - gustOffset - gustBand * CGFloat(gusts[position] / gustTop) - 9)
                        ),
                        width: width,
                        color: Color.teal.mix(with: .white, by: 0.45)
                    )
                }
            }
        case .wind:
            let gusts = series(model.windgusts)
            let speeds = series(model.windspeed)
            let top = max(gusts.max() ?? 0, speeds.max() ?? 0, 1)
            let band = chartHeight * 0.7
            drawLine(
                context: &context, values: speeds, color: .teal.mix(with: .black, by: 0.35),
                width: 1.5, band: band, offset: 0, chartHeight: chartHeight, x: x, maxValue: top
            )
            drawLine(
                context: &context, values: gusts, color: .teal,
                width: 2, band: band, offset: 0, chartHeight: chartHeight, x: x, maxValue: top
            )
            if let peak = gusts.indices.max(by: { gusts[$0] < gusts[$1] }) {
                drawLabel(
                    context: &context,
                    text: "\(Int(gusts[peak].rounded())) \(model.windUnitString)",
                    at: CGPoint(x: x(peak), y: max(6, chartHeight - band * CGFloat(gusts[peak] / top) - 10)),
                    width: width
                )
            }
        case .night:
            let temps = series(model.temperature)
            drawLine(
                context: &context, values: temps, color: .orange,
                width: 2, band: chartHeight * 0.55, offset: chartHeight * 0.15,
                chartHeight: chartHeight, x: x, normalizeToOwnRange: true
            )
            if let low = temps.indices.min(by: { temps[$0] < temps[$1] }) {
                drawLabel(
                    context: &context,
                    text: HourlyFormatting.temperatureString(temps[low]),
                    at: CGPoint(x: x(low), y: chartHeight - 10),
                    width: width
                )
            }
        case .day:
            let rates = series(model.precipitation)
            drawBars(
                context: &context, rates: rates, snow: series(model.snowfall),
                maxValue: max(rates.max() ?? 0, 2.5),
                band: chartHeight * 0.4, chartHeight: chartHeight, slot: slot, x: x
            )
            let temps = series(model.temperature)
            drawLine(
                context: &context, values: temps, color: .orange,
                width: 2, band: chartHeight * 0.55, offset: chartHeight * 0.12,
                chartHeight: chartHeight, x: x, normalizeToOwnRange: true
            )
            if let high = temps.indices.max(by: { temps[$0] < temps[$1] }) {
                drawLabel(
                    context: &context,
                    text: HourlyFormatting.temperatureString(temps[high]),
                    at: CGPoint(x: x(high), y: max(6, chartHeight - chartHeight * 0.67 - 10)),
                    width: width
                )
            }
            if let low = temps.indices.min(by: { temps[$0] < temps[$1] }) {
                drawLabel(
                    context: &context,
                    text: HourlyFormatting.temperatureString(temps[low]),
                    at: CGPoint(x: x(low), y: max(6, chartHeight - chartHeight * 0.12 - 10)),
                    width: width
                )
            }
            for highlight in chapter.highlights {
                switch highlight {
                case .pressure:
                    drawLine(
                        context: &context, values: series(model.pressure), color: .purple,
                        width: 1.5, band: chartHeight * 0.3, offset: chartHeight * 0.55,
                        chartHeight: chartHeight, x: x, normalizeToOwnRange: true
                    )
                }
            }
        case .sunEvent, .radar, .alert:
            break
        }

        drawAxis(context: &context, indices: indices, chartHeight: chartHeight, width: width, x: x)
    }

    private func drawRadar(context: inout GraphicsContext, size: CGSize) {
        var points = zip(model.radarTimes, model.radarRates)
            .filter { $0.0 >= chapter.range.lowerBound - 120 && $0.0 <= chapter.range.upperBound + 120 }
        if points.count < 2 {
            points = zip(model.radarTimes, model.radarRates)
                .filter { $0.0 >= chapter.range.lowerBound - 900 && $0.0 <= chapter.range.upperBound + 900 }
        }
        guard points.count > 1 else { return }
        let width = size.width
        let chartHeight = size.height - Self.axisHeight
        let span = max(points.last!.0 - points.first!.0, 1)
        let maxRate = max(points.map { $0.1 }.max() ?? 0, 0.5)
        let band = chartHeight * 0.7

        func x(_ time: Double) -> CGFloat {
            CGFloat((time - points.first!.0) / span) * width
        }
        func y(_ rate: Double) -> CGFloat {
            chartHeight - band * CGFloat(rate / maxRate)
        }

        context.fill(
            Path(CGRect(x: 0, y: chartHeight - 0.5, width: width, height: 1)),
            with: .color(.white.opacity(0.15))
        )

        var line = Path()
        var area = Path()
        area.move(to: CGPoint(x: x(points[0].0), y: chartHeight))
        for (position, point) in points.enumerated() {
            let place = CGPoint(x: x(point.0), y: y(point.1))
            if position == 0 {
                line.move(to: place)
            } else {
                line.addLine(to: place)
            }
            area.addLine(to: place)
        }
        area.addLine(to: CGPoint(x: x(points.last!.0), y: chartHeight))
        area.closeSubpath()
        context.fill(area, with: .color(.hourlyRain.opacity(0.25)))
        context.stroke(
            line,
            with: .color(.hourlyRain),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )

        if let peak = points.max(by: { $0.1 < $1.1 }), peak.1 >= 0.1 {
            let rate = model.precipitationUnit.lowercased() == "inch" ? peak.1 / 25.4 : peak.1
            drawLabel(
                context: &context,
                text: "\(rate.formatted(.number.precision(.fractionLength(1)))) \(model.precipitationUnit)/h",
                at: CGPoint(x: x(peak.0), y: max(6, y(peak.1) - 10)),
                width: width
            )
        }

        let font = Font.system(size: 10, weight: .medium)
        for fraction in [0.0, 0.5, 1.0] {
            let time = points.first!.0 + span * fraction
            let label = context.resolve(
                Text(verbatim: HourlyFormatting.timeString(timestamp: time, timeZone: model.timeZone))
                    .font(font)
                    .foregroundStyle(.white.opacity(0.55))
            )
            let labelSize = label.measure(in: CGSize(width: 100, height: 20))
            let clampedX = min(max(x(time), labelSize.width / 2), width - labelSize.width / 2)
            context.draw(
                label,
                at: CGPoint(x: clampedX, y: chartHeight + Self.axisHeight / 2 + 2),
                anchor: .center
            )
        }
    }

    // MARK: - Primitives

    private func drawBars(
        context: inout GraphicsContext,
        rates: [Double],
        snow: [Double],
        maxValue: Double,
        band: CGFloat,
        chartHeight: CGFloat,
        slot: CGFloat,
        x: (Int) -> CGFloat
    ) {
        let barWidth = max(4, slot * 0.55)
        for (position, rate) in rates.enumerated() where rate > 0 {
            let height = max(3, band * CGFloat(rate / maxValue))
            let isSnow = position < snow.count && snow[position] > 0
            context.fill(
                Path(
                    roundedRect: CGRect(
                        x: x(position) - barWidth / 2,
                        y: chartHeight - height,
                        width: barWidth,
                        height: height
                    ),
                    cornerRadii: RectangleCornerRadii(topLeading: 3, topTrailing: 3)
                ),
                with: .color((isSnow ? Color.cyan : .hourlyRain).opacity(0.9))
            )
        }
    }

    private func drawLine(
        context: inout GraphicsContext,
        values: [Double],
        color: Color,
        width: CGFloat,
        band: CGFloat,
        offset: CGFloat,
        chartHeight: CGFloat,
        x: (Int) -> CGFloat,
        maxValue: Double? = nil,
        normalizeToOwnRange: Bool = false
    ) {
        guard values.count > 1 else { return }
        let low = normalizeToOwnRange ? (values.min() ?? 0) : 0
        let high = maxValue ?? (normalizeToOwnRange ? (values.max() ?? 1) : (values.max() ?? 1) * 1.15)
        let span = max(high - low, 0.0001)

        var path = Path()
        for (position, value) in values.enumerated() {
            let fraction = (value - low) / span
            let point = CGPoint(
                x: x(position),
                y: chartHeight - offset - band * CGFloat(fraction)
            )
            if position == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawLabel(
        context: inout GraphicsContext,
        text: String,
        at point: CGPoint,
        width: CGFloat,
        color: Color = .white
    ) {
        let resolved = context.resolve(
            Text(verbatim: text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
        )
        let size = resolved.measure(in: CGSize(width: 200, height: 20))
        let clampedX = min(max(point.x, size.width / 2 + 2), width - size.width / 2 - 2)
        context.draw(resolved, at: CGPoint(x: clampedX, y: point.y), anchor: .center)
    }

    private func drawAxis(
        context: inout GraphicsContext,
        indices: [Int],
        chartHeight: CGFloat,
        width: CGFloat,
        x: (Int) -> CGFloat
    ) {
        let step = indices.count <= 7 ? 1 : indices.count <= 14 ? 3 : 6
        let font = Font.system(size: 10, weight: .medium)
        for (position, index) in indices.enumerated() where position % step == 0 {
            let label = context.resolve(
                Text(verbatim: SettingService.formattedTime(
                    Date(timeIntervalSince1970: model.times[index]),
                    timeZone: model.timeZone,
                    showsMinutes: false
                ))
                .font(font)
                .foregroundStyle(.white.opacity(0.55))
            )
            let size = label.measure(in: CGSize(width: 100, height: 20))
            let clampedX = min(max(x(position), size.width / 2), width - size.width / 2)
            context.draw(
                label,
                at: CGPoint(x: clampedX, y: chartHeight + Self.axisHeight / 2 + 2),
                anchor: .center
            )
        }
    }
}
