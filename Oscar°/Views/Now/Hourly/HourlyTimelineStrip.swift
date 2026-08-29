import SwiftUI

/// The hourly detail timeline: a 48-hour window over the full 14-day range,
/// rendered for whatever lens is active — line stack, optional precipitation
/// bars, cloud ribbons, or area fill, night shading, sticky day labels,
/// per-day extremes, value gridlines, hour ticks, and the playhead.
///
/// The playhead is pinned to the center: dragging moves the timeline beneath
/// it, which scrubs the stage. A tap glides the tapped time under the
/// playhead, and a fast pan coasts on with the gesture's momentum. Past hours
/// render faded.
///
/// Canvas, not Charts: at this height features are a few points tall and the
/// whole strip redraws per pan/scrub frame — same reasoning as the meteogram
/// minimap.
struct HourlyTimelineStrip: View {
    let model: HourlyTimelineModel
    let lens: HourlyLens

    @State private var isDragging = false
    @State private var readoutSize: CGSize = .zero

    private static let axisHeight: CGFloat = 16

    var body: some View {
        let scrubTime = model.scrubTime
        let windowStart = model.windowStart
        let nightRanges = model.nightRanges
        let layout = model.layout(for: lens)

        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            Canvas { context, size in
                draw(
                    context: &context,
                    size: size,
                    layout: layout,
                    scrubTime: scrubTime,
                    windowStart: windowStart,
                    nightRanges: nightRanges
                )
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            model.beginPan()
                        }
                        model.pan(byFraction: value.translation.width / width)
                    }
                    .onEnded { value in
                        isDragging = false
                        if abs(value.translation.width) < 8, abs(value.translation.height) < 8 {
                            model.endPan()
                            model.tap(atFraction: min(max(0, value.location.x / width), 1))
                        } else {
                            let coast = (value.predictedEndTranslation.width - value.translation.width) / width
                            model.endPan(coastFraction: coast)
                        }
                    }
            )
            .overlay(alignment: .topLeading) {
                // Below the day-label row along the chart's top edge.
                HourlyReadoutBox(model: model, layout: layout)
                    .onGeometryChange(for: CGSize.self, of: { $0.size }) { readoutSize = $0 }
                    .offset(x: readoutX(width: width, layout: layout), y: 22)
                    .allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.selection, trigger: model.hourTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Zeitleiste"))
        .accessibilityValue(Text(verbatim: model.accessibilityValue))
        .accessibilityAdjustableAction { direction in
            model.nudge(hours: direction == .increment ? 1 : -1)
        }
    }

    /// The readout box sits right of the playhead like the old tooltip; when
    /// its rows are wide enough to reach into the right-edge value labels
    /// (Bodenwassergehalt), it flips to the faded past side instead — the old
    /// annotation's fit-to-chart behavior.
    private func readoutX(width: CGFloat, layout: HourlyLensLayout) -> CGFloat {
        let trailing = width / 2 + 10
        guard layout.bands.isEmpty else { return trailing }
        // Rough width of the gridline labels (9.5 pt font): enough precision
        // to decide the flip.
        let reserved = CGFloat(layout.extremeFormat(layout.domain.upperBound).count) * 5.5 + 12
        guard trailing + readoutSize.width > width - reserved else { return trailing }
        return max(width / 2 - 10 - readoutSize.width, 2)
    }

    // MARK: - Drawing

    private func draw(
        context: inout GraphicsContext,
        size: CGSize,
        layout: HourlyLensLayout,
        scrubTime: Double,
        windowStart: Double,
        nightRanges: [ClosedRange<Double>]
    ) {
        guard model.hasData else { return }
        let width = size.width
        let chartHeight = size.height - Self.axisHeight
        let windowSeconds = model.windowSeconds
        let nowTime = Date.now.timeIntervalSince1970

        func x(_ time: Double) -> CGFloat {
            CGFloat((time - windowStart) / windowSeconds) * width
        }

        let nowX = x(nowTime)

        let domain = layout.domain
        let span = max(domain.upperBound - domain.lowerBound, 0.0001)
        func yOf(_ value: Double) -> CGFloat {
            let fraction = (value - domain.lowerBound) / span
            return chartHeight * (0.84 - 0.58 * CGFloat(fraction))
        }
        func barHeight(_ value: Double) -> CGFloat {
            max(2, CGFloat(value / model.precipitationMax) * chartHeight * 0.5)
        }

        // Past hours draw faded; split at the now boundary. (No dash — with
        // stacked series the dashes read as noise.)
        func splitStroke(_ path: Path, color: Color, opacity: Double, lineWidth: CGFloat, dashed: Bool) {
            if nowX > 0 {
                var past = context
                past.clip(to: Path(CGRect(x: 0, y: 0, width: min(nowX, width), height: size.height)))
                past.stroke(
                    path,
                    with: .color(color.opacity(opacity * 0.45)),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: dashed ? [4, 3] : []
                    )
                )
            }
            if nowX < width {
                var future = context
                future.clip(to: Path(CGRect(x: max(nowX, 0), y: 0, width: width - max(nowX, 0), height: size.height)))
                future.stroke(
                    path,
                    with: .color(color.opacity(opacity)),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: dashed ? [4, 3] : []
                    )
                )
            }
        }
        func splitFill(_ path: Path, color: Color, opacity: Double) {
            if nowX > 0 {
                var past = context
                past.clip(to: Path(CGRect(x: 0, y: 0, width: min(nowX, width), height: size.height)))
                past.fill(path, with: .color(color.opacity(opacity * 0.5)))
            }
            if nowX < width {
                var future = context
                future.clip(to: Path(CGRect(x: max(nowX, 0), y: 0, width: width - max(nowX, 0), height: size.height)))
                future.fill(path, with: .color(color.opacity(opacity)))
            }
        }

        for range in nightRanges {
            let x0 = max(0, x(range.lowerBound))
            let x1 = min(width, x(range.upperBound))
            guard x1 > x0 else { continue }
            context.fill(
                Path(CGRect(x: x0, y: 0, width: x1 - x0, height: chartHeight)),
                with: .color(.black.opacity(0.1))
            )
        }

        // Text placed on the chart registers here so later labels can dodge
        // it; whatever cannot find a free spot skips drawing.
        var labelRects: [CGRect] = []

        // Value gridlines with right-edge labels (line lenses only).
        if layout.bands.isEmpty {
            let step = Self.niceStep(span / 3)
            let gridFont = Font.system(size: 9.5, weight: .medium)
            var value = (domain.lowerBound / step).rounded(.up) * step
            while value <= domain.upperBound {
                let gridY = yOf(value)
                if gridY > 16, gridY < chartHeight - 6 {
                    var gridPath = Path()
                    gridPath.move(to: CGPoint(x: 0, y: gridY))
                    gridPath.addLine(to: CGPoint(x: width, y: gridY))
                    context.stroke(
                        gridPath,
                        with: .color(.white.opacity(0.1)),
                        style: StrokeStyle(lineWidth: 0.75, dash: [2, 3])
                    )
                    let label = context.resolve(
                        Text(verbatim: layout.extremeFormat(value))
                            .font(gridFont)
                            .foregroundStyle(.white.opacity(0.6))
                    )
                    let labelSize = label.measure(in: CGSize(width: 200, height: 20))
                    labelRects.append(CGRect(
                        x: width - 4 - labelSize.width,
                        y: gridY - 2 - labelSize.height,
                        width: labelSize.width,
                        height: labelSize.height
                    ))
                    context.draw(label, at: CGPoint(x: width - 4, y: gridY - 2), anchor: .bottomTrailing)
                }
                value += step
            }
        }

        let firstTime = model.domain.lowerBound
        let firstIndex = max(0, Int((windowStart - firstTime) / 3_600) - 1)
        let lastIndex = min(model.times.count - 1, firstIndex + Int(windowSeconds / 3_600) + 2)
        guard firstIndex <= lastIndex else { return }

        for band in layout.bands {
            let centerY = chartHeight * band.centerFraction
            let maxHalf = chartHeight * 0.11
            var top: [CGPoint] = []
            var bottom: [CGPoint] = []
            for index in firstIndex...lastIndex where index < band.values.count {
                let half = maxHalf * CGFloat(band.values[index] / 100)
                let pointX = x(model.times[index])
                top.append(CGPoint(x: pointX, y: centerY - half))
                bottom.append(CGPoint(x: pointX, y: centerY + half))
            }
            guard top.count > 1 else { continue }
            var ribbon = Path()
            ribbon.move(to: top[0])
            for point in top.dropFirst() { ribbon.addLine(to: point) }
            for point in bottom.reversed() { ribbon.addLine(to: point) }
            ribbon.closeSubpath()
            splitFill(ribbon, color: .hourlyCloud, opacity: 0.85)

            // Shadowed so the label stays readable on the white ribbon in
            // dark mode too.
            var labelContext = context
            labelContext.addFilter(.shadow(color: .black.opacity(0.35), radius: 1.5))
            let label = labelContext.resolve(
                Text(verbatim: band.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            )
            labelContext.draw(label, at: CGPoint(x: 6, y: centerY), anchor: .leading)
        }

        if layout.showsBars {
            let barWidth = max(2, width * CGFloat(3_600 / windowSeconds) - 1.5)
            for index in firstIndex...lastIndex where index < model.precipitation.count {
                let value = model.precipitation[index]
                guard value > 0 else { continue }
                let rect = CGRect(
                    x: x(model.times[index]) - barWidth / 2,
                    y: chartHeight - barHeight(value),
                    width: barWidth,
                    height: barHeight(value)
                )
                let isSnow = index < model.snowfall.count && model.snowfall[index] > 0
                let isPast = model.times[index] < nowTime
                context.fill(
                    Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(topLeading: 2, topTrailing: 2)),
                    with: .color((isSnow ? Color.cyan : Color.hourlyRain)
                        .opacity(layout.barsAlpha * (isPast ? 0.45 : 1)))
                )
            }
        }

        for line in layout.lines {
            var path = Path()
            var started = false
            for index in firstIndex...lastIndex where index < line.values.count {
                let point = CGPoint(x: x(model.times[index]), y: yOf(line.values[index]))
                if started {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    started = true
                }
            }
            splitStroke(path, color: line.color, opacity: line.opacity, lineWidth: line.width, dashed: line.dashed)
        }

        if layout.fillsPrimary, let primary = layout.primary {
            var area = Path()
            var started = false
            for index in firstIndex...lastIndex where index < primary.values.count {
                let point = CGPoint(x: x(model.times[index]), y: yOf(primary.values[index]))
                if started {
                    area.addLine(to: point)
                } else {
                    area.move(to: CGPoint(x: point.x, y: chartHeight))
                    area.addLine(to: point)
                    started = true
                }
            }
            if started {
                area.addLine(to: CGPoint(
                    x: x(model.times[min(lastIndex, primary.values.count - 1)]),
                    y: chartHeight
                ))
                area.closeSubpath()
                splitFill(area, color: primary.color, opacity: 0.14)
            }
        }

        if layout.showsDirectionArrows, let primary = layout.primary {
            for index in firstIndex...lastIndex
            where index < model.winddirection.count && index < primary.values.count {
                guard Int((model.times[index] / 3_600).rounded()) % 6 == 3 else { continue }
                let arrowX = x(model.times[index])
                guard arrowX > 10, arrowX < width - 10 else { continue }
                let isPast = model.times[index] < nowTime
                var rotated = context
                rotated.translateBy(x: arrowX, y: yOf(primary.values[index]))
                rotated.rotate(by: .degrees(model.winddirection[index] + 180))
                // A darker-teal outline hugging the glyph (the same symbol
                // drawn offset in a ring behind it) lifts the arrow off the
                // line.
                let outline = rotated.resolve(
                    Text(Image(systemName: "location.north.fill"))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.teal.mix(with: .black, by: 0.35).opacity(isPast ? 0.42 : 1))
                )
                for angle in stride(from: 0.0, to: 360, by: 45) {
                    let radians = angle * .pi / 180
                    rotated.draw(
                        outline,
                        at: CGPoint(x: cos(radians), y: sin(radians)),
                        anchor: .center
                    )
                }
                let symbol = rotated.resolve(
                    Text(Image(systemName: "location.north.fill"))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.teal.opacity(isPast ? 0.42 : 1))
                )
                rotated.draw(symbol, at: .zero, anchor: .center)
            }
        }

        let dayFont = Font.system(size: 11, weight: .semibold)
        for (index, mark) in model.dayMarks.enumerated() {
            let startX = x(mark.start)
            let nextStart = index + 1 < model.dayMarks.count
                ? model.dayMarks[index + 1].start
                : model.domain.upperBound
            let endX = x(nextStart)

            if index > 0, startX > -1, startX < width + 1 {
                var rule = Path()
                rule.move(to: CGPoint(x: startX, y: 0))
                rule.addLine(to: CGPoint(x: startX, y: chartHeight))
                context.stroke(
                    rule,
                    with: .color(.white.opacity(0.18)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
            }

            guard endX > 30, startX < width - 10 else { continue }
            let resolved = context.resolve(
                Text(verbatim: mark.label)
                    .font(dayFont)
                    .foregroundStyle(.white.opacity(0.85))
            )
            let textSize = resolved.measure(in: CGSize(width: 200, height: 20))
            let labelX = min(max(startX + 6, 6), endX - textSize.width - 6)
            guard labelX + textSize.width < width - 40 else { continue }
            labelRects.append(CGRect(x: labelX, y: 5, width: textSize.width, height: textSize.height))
            context.draw(resolved, at: CGPoint(x: labelX, y: 5), anchor: .topLeading)
        }

        let valueFont = Font.system(size: 10.5, weight: .semibold)
        for extreme in layout.extremes {
            let markX = x(extreme.timestamp)
            guard markX > 14, markX < width - 14 else { continue }
            let markY = yOf(extreme.value)
            context.fill(
                Path(ellipseIn: CGRect(x: markX - 2.5, y: markY - 2.5, width: 5, height: 5)),
                with: .color(layout.primaryColor)
            )
            let label = context.resolve(
                Text(verbatim: layout.extremeFormat(extreme.value))
                    .font(valueFont)
                    .foregroundStyle(.white)
            )
            let labelSize = label.measure(in: CGSize(width: 200, height: 20))
            // Preferred side first (above the highs, below the lows), the
            // other side if that spot is taken, no label if both are — the
            // dot alone marks the extreme then.
            let clampedX = min(max(markX - labelSize.width / 2, 2), width - labelSize.width - 2)
            let aboveY = max(markY - 7 - labelSize.height, 3)
            let belowY = min(markY + 7, chartHeight - labelSize.height - 3)
            let candidates = (extreme.isHigh ? [aboveY, belowY] : [belowY, aboveY]).map {
                CGRect(x: clampedX, y: $0, width: labelSize.width, height: labelSize.height)
            }
            guard let rect = candidates.first(where: { candidate in
                !labelRects.contains { $0.insetBy(dx: -3, dy: -1).intersects(candidate) }
            }) else { continue }
            labelRects.append(rect)
            context.draw(label, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }

        if nowX > 0, nowX < width {
            context.fill(
                Path(CGRect(x: nowX - 0.5, y: 0, width: 1, height: chartHeight)),
                with: .color(.white.opacity(0.35))
            )
        }

        var calendar = Calendar.current
        calendar.timeZone = model.timeZone
        let tickFont = Font.system(size: 10, weight: .medium)
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour],
            from: Date(timeIntervalSince1970: windowStart)
        )
        components.hour = ((components.hour ?? 0) / 6) * 6
        components.minute = 0
        var tickDate = calendar.date(from: components) ?? Date(timeIntervalSince1970: windowStart)
        var guardCounter = 0
        while tickDate.timeIntervalSince1970 < windowStart + windowSeconds, guardCounter < 16 {
            guardCounter += 1
            let tickX = x(tickDate.timeIntervalSince1970)
            let hour = calendar.component(.hour, from: tickDate)
            // The window can extend past the data near the edges; keep the
            // axis empty there so the void reads as "no forecast".
            let inData = tickDate.timeIntervalSince1970 >= model.domain.lowerBound - 1_800
                && tickDate.timeIntervalSince1970 <= model.domain.upperBound + 1_800
            if inData {
                // Midnight already carries the stronger day rule.
                if hour != 0, tickX > 0, tickX < width {
                    context.fill(
                        Path(CGRect(x: tickX - 0.375, y: 0, width: 0.75, height: chartHeight)),
                        with: .color(.white.opacity(0.1))
                    )
                }
                if tickX > 14, tickX < width - 14 {
                    let label = context.resolve(
                        Text(verbatim: SettingService.formattedTime(
                            tickDate, timeZone: model.timeZone, showsMinutes: false
                        ))
                        .font(tickFont)
                        .foregroundStyle(.white.opacity(0.6))
                    )
                    context.draw(label, at: CGPoint(x: tickX, y: chartHeight + Self.axisHeight / 2 + 2))
                }
            }
            guard let next = calendar.date(byAdding: .hour, value: 6, to: tickDate) else { break }
            tickDate = next
        }

        // Playhead: pinned to the strip's center; the timeline moves beneath it.
        let headX = x(scrubTime)
        context.fill(
            Path(CGRect(x: headX - 0.75, y: 0, width: 1.5, height: chartHeight)),
            with: .color(.white.opacity(0.95))
        )
        func interpolated(_ values: [Double]) -> Double? {
            AtmosphereWeatherMapper.interpolatedValue(at: scrubTime, times: model.times, values: values)
        }

        // Dots mark where the playhead crosses each series; the values live in
        // the readout box overlaid next to the playhead, where rows keep a
        // fixed order instead of chasing the lines.
        for line in layout.lines {
            guard let value = interpolated(line.values) else { continue }
            let dot = Path(ellipseIn: CGRect(x: headX - 4, y: yOf(value) - 4, width: 8, height: 8))
            context.fill(dot, with: .color(.white))
            context.stroke(dot, with: .color(line.color), lineWidth: 2)
        }
        if layout.showsBars {
            let rate = interpolated(model.precipitation) ?? 0
            if rate >= 0.05 {
                let isSnow = (interpolated(model.snowfall) ?? 0) > 0
                let dot = Path(ellipseIn: CGRect(
                    x: headX - 4, y: chartHeight - barHeight(rate) - 4, width: 8, height: 8
                ))
                context.fill(dot, with: .color(.white))
                context.stroke(dot, with: .color(isSnow ? .cyan : .hourlyRain), lineWidth: 2)
            }
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

/// The playhead readout, styled like the retired chart cards' selection
/// tooltip: a frosted box beside the playhead, only always visible now. Each
/// series is a dot + label + value row in the lens' fixed order (primary
/// first, then by altitude/depth), so rows never trade places while the
/// lines cross. The rows double as the legend.
private struct HourlyReadoutBox: View {
    let model: HourlyTimelineModel
    let layout: HourlyLensLayout

    private struct Row: Identifiable {
        let id: Int
        let color: Color
        let label: String?
        let value: String
    }

    var body: some View {
        let rows = self.rows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: model.clockLabel)
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.bottom, 1)
                ForEach(rows) { row in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(row.color)
                            .frame(width: 6, height: 6)
                        if let label = row.label {
                            Text(verbatim: label)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        Text(verbatim: row.value)
                            .foregroundStyle(.white)
                    }
                }
            }
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(8)
            .background(.ultraThinMaterial.opacity(0.9))
            .clipShape(.rect(cornerRadius: 8))
            .shadow(radius: 4)
        }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        for line in layout.lines.reversed() {
            guard let value = model.sample(line.values) else { continue }
            rows.append(Row(
                id: rows.count,
                color: line.color,
                label: line.label,
                value: layout.extremeFormat(value)
            ))
        }
        // The precipitation row stays put when it is dry — a 0 keeps the box
        // from resizing mid-scrub and is an answer in itself.
        if layout.showsBars, let barsLabel = layout.barsLabel {
            let rate = model.sample(model.precipitation) ?? 0
            let isSnow = (model.sample(model.snowfall) ?? 0) > 0
            rows.append(Row(
                id: rows.count,
                color: isSnow ? .cyan : .hourlyRain,
                label: barsLabel,
                value: "\(rate.formatted(.number.precision(.fractionLength(1)))) \(model.precipitationUnit)"
            ))
        }
        for band in layout.bands {
            guard let value = model.sample(band.values) else { continue }
            rows.append(Row(
                id: rows.count,
                color: .hourlyCloud,
                label: band.label,
                value: layout.extremeFormat(value)
            ))
        }
        return rows
    }
}

/// The day rail at the sheet's bottom: 14 days at a glance — white
/// temperature line, precipitation ticks — with the 48-hour viewport box
/// around the playhead. Lens-independent: the rail is navigation, not data
/// display. Dragging the box (or tapping elsewhere) scrubs; the same
/// grab-offset feel as the meteogram minimap.
struct HourlyTimelineMinimap: View {
    let model: HourlyTimelineModel

    @State private var grabOffset: Double?

    private static let chartHeight: CGFloat = 40
    private static let labelHeight: CGFloat = 13

    var body: some View {
        let scrubTime = model.scrubTime
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            Canvas { context, size in
                draw(context: &context, size: size, scrubTime: scrubTime)
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let domain = model.domain
                        let seconds = max(domain.upperBound - domain.lowerBound, 1)
                        let fraction = Double(min(max(0, value.location.x / width), 1))
                        if grabOffset == nil {
                            let startFraction = Double(min(max(0, value.startLocation.x / width), 1))
                            let startTime = domain.lowerBound + startFraction * seconds
                            let delta = startTime - model.scrubTime
                            grabOffset = abs(delta) < model.windowSeconds / 2 ? delta : 0
                        }
                        model.scrub(to: domain.lowerBound + fraction * seconds - (grabOffset ?? 0))
                    }
                    .onEnded { _ in grabOffset = nil }
            )
        }
        .frame(height: Self.chartHeight + Self.labelHeight)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .cardBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardBorder(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Übersicht"))
        .accessibilityValue(Text(verbatim: model.timeLabel))
        .accessibilityAdjustableAction { direction in
            model.nudge(hours: direction == .increment ? 24 : -24)
        }
    }

    private func draw(
        context: inout GraphicsContext,
        size: CGSize,
        scrubTime: Double
    ) {
        guard model.hasData else { return }
        let width = size.width
        let height = Self.chartHeight
        let domain = model.domain
        let seconds = max(domain.upperBound - domain.lowerBound, 1)

        func x(_ time: Double) -> CGFloat {
            CGFloat((time - domain.lowerBound) / seconds) * width
        }

        for range in model.nightRanges {
            let x0 = max(0, x(range.lowerBound))
            let x1 = min(width, x(range.upperBound))
            guard x1 > x0 else { continue }
            context.fill(
                Path(CGRect(x: x0, y: 0, width: x1 - x0, height: height)),
                with: .color(.black.opacity(0.12))
            )
        }

        let times = model.times
        let barWidth = max(1, width * CGFloat(7_200 / seconds))
        for (index, value) in model.precipitation.enumerated() where value > 0 {
            guard index < times.count else { break }
            let barH = max(1.5, CGFloat(value / model.precipitationMax) * (height * 0.45))
            context.fill(
                Path(CGRect(x: x(times[index]) - barWidth / 2, y: height - barH, width: barWidth, height: barH)),
                with: .color(.hourlyRain.opacity(0.9))
            )
        }

        let temperature = model.temperature
        if var low = temperature.min(), var high = temperature.max() {
            let pad = max((high - low) * 0.08, 0.5)
            low -= pad
            high += pad
            let valueSpan = max(high - low, 0.0001)
            var line = Path()
            var started = false
            for index in stride(from: 0, to: min(times.count, temperature.count), by: 2) {
                let fraction = (temperature[index] - low) / valueSpan
                let point = CGPoint(x: x(times[index]), y: height * (0.78 - 0.56 * CGFloat(fraction)))
                if started {
                    line.addLine(to: point)
                } else {
                    line.move(to: point)
                    started = true
                }
            }
            context.stroke(line, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
        }

        let labelFont = Font.system(size: 9.5, weight: .medium)
        let dayWidth = width * CGFloat(86_400 / seconds)
        for (index, mark) in model.dayMarks.enumerated() {
            let dayX = x(mark.start)
            if index > 0 {
                var rule = Path()
                rule.move(to: CGPoint(x: dayX, y: 0))
                rule.addLine(to: CGPoint(x: dayX, y: height))
                context.stroke(
                    rule,
                    with: .color(.white.opacity(0.15)),
                    style: StrokeStyle(lineWidth: 0.75, dash: [2, 2.5])
                )
            }
            guard dayWidth > 30 || index % 2 == 0 else { continue }
            let label = context.resolve(
                Text(verbatim: mark.shortLabel).font(labelFont).foregroundStyle(.white.opacity(0.7))
            )
            context.draw(label, at: CGPoint(x: dayX + 3, y: height + 2), anchor: .topLeading)
        }

        let nowX = x(Date.now.timeIntervalSince1970)
        if nowX > 0, nowX < width {
            context.fill(
                Path(CGRect(x: nowX - 0.5, y: 0, width: 1, height: height)),
                with: .color(.white.opacity(0.4))
            )
        }

        let viewportRect = CGRect(
            x: x(scrubTime - model.windowSeconds / 2),
            y: 0.75,
            width: x(scrubTime + model.windowSeconds / 2) - x(scrubTime - model.windowSeconds / 2),
            height: height - 1.5
        )
        let viewport = Path(roundedRect: viewportRect, cornerRadius: 6)
        context.fill(viewport, with: .color(.white.opacity(0.1)))
        context.stroke(viewport, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
    }
}
