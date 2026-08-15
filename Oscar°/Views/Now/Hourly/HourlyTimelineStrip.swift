import SwiftUI

/// The hourly detail timeline: a 48-hour window over the full 14-day range,
/// rendered for whatever lens is active — line stack, optional precipitation
/// bars, cloud ribbons, or area fill, night shading, sticky day labels,
/// per-day extremes, value gridlines, hour ticks, and the playhead.
///
/// The playhead is pinned to the center: dragging moves the timeline beneath
/// it, which scrubs the stage. A tap glides the tapped time under the
/// playhead, and a fast pan coasts on with the gesture's momentum. Past hours
/// render dashed and faded, matching the app's other charts.
///
/// Canvas, not Charts: at this height features are a few points tall and the
/// whole strip redraws per pan/scrub frame — same reasoning as the meteogram
/// minimap.
struct HourlyTimelineStrip: View {
    let model: HourlyTimelineModel

    @State private var isDragging = false

    private static let axisHeight: CGFloat = 16

    var body: some View {
        let scrubTime = model.scrubTime
        let windowStart = model.windowStart
        let nightRanges = model.nightRanges
        let layout = model.layout(for: model.lens)

        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                header(model.cardHeader)
                if model.isAwayFromNow {
                    backToNowButton
                }
            }
            .animation(.snappy, value: model.isAwayFromNow)

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
            }
            .frame(maxHeight: .infinity)

            legendRow(model.lensStats)
                .padding(.top, 2)
        }
        .padding(14)
        .cardBackground(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .cardBorder(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .sensoryFeedback(.selection, trigger: model.hourTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Zeitleiste"))
        .accessibilityValue(Text(verbatim: model.accessibilityValue))
        .accessibilityAdjustableAction { direction in
            model.nudge(hours: direction == .increment ? 1 : -1)
        }
    }

    // MARK: - Header + legend

    private func header(_ header: HourlyTimelineModel.CardHeader) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(header.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.7))
            HStack(spacing: 8) {
                Text(verbatim: header.value)
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                if let badge = header.badge {
                    Text(verbatim: badge)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(header.color.opacity(0.95), in: .capsule)
                        .foregroundStyle(.white)
                }
            }
            Text(header.subtitle)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.65))
                .padding(.top, 1)
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backToNowButton: some View {
        Button {
            model.glide(to: Date.now.timeIntervalSince1970)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption2.weight(.bold))
                Text(verbatim: model.nowDeltaLabel)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(.white.opacity(0.35)), in: Capsule())
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .accessibilityLabel(Text("Zur aktuellen Zeit springen"))
    }

    private func legendRow(_ stats: [HourlyTimelineModel.HUDStat]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(stats.filter { $0.color != nil }) { stat in
                    HStack(spacing: 5) {
                        HourlySeriesSwatch(color: stat.color, kind: stat.swatch)
                        Text(verbatim: stat.label)
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
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

        // Past hours draw dashed and faded; split at the now boundary.
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
                        dash: dashed ? [4, 3] : [3, 3.5]
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
                with: .color(.black.opacity(0.16))
            )
        }

        // Value gridlines with right-edge labels (line lenses only).
        if layout.bands.isEmpty, !layout.ridesBars {
            let step = Self.niceStep(span / 3)
            let gridFont = Font.system(size: 8.5, weight: .medium)
            var value = (domain.lowerBound / step).rounded(.up) * step
            while value <= domain.upperBound {
                let gridY = yOf(value)
                if gridY > 16, gridY < chartHeight - 6 {
                    var gridPath = Path()
                    gridPath.move(to: CGPoint(x: 0, y: gridY))
                    gridPath.addLine(to: CGPoint(x: width, y: gridY))
                    context.stroke(
                        gridPath,
                        with: .color(.primary.opacity(0.08)),
                        style: StrokeStyle(lineWidth: 0.75, dash: [2, 3])
                    )
                    let label = context.resolve(
                        Text(verbatim: layout.extremeFormat(value))
                            .font(gridFont)
                            .foregroundStyle(.primary.opacity(0.55))
                    )
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
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
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
                let symbol = rotated.resolve(
                    Text(Image(systemName: "location.north.fill"))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.teal.opacity(isPast ? 0.42 : 1))
                )
                rotated.draw(symbol, at: .zero, anchor: .center)
            }
        }

        let valueFont = Font.system(size: 10, weight: .semibold)
        for extreme in layout.extremes {
            let markX = x(extreme.timestamp)
            guard markX > 14, markX < width - 14 else { continue }
            let markY = layout.ridesBars
                ? chartHeight - barHeight(extreme.value)
                : yOf(extreme.value)
            context.fill(
                Path(ellipseIn: CGRect(x: markX - 2.5, y: markY - 2.5, width: 5, height: 5)),
                with: .color(layout.primaryColor)
            )
            let label = context.resolve(
                Text(verbatim: layout.extremeFormat(extreme.value))
                    .font(valueFont)
                    .foregroundStyle(.primary)
            )
            if extreme.isHigh {
                context.draw(label, at: CGPoint(x: markX, y: max(markY - 7, 20)), anchor: .bottom)
            } else {
                context.draw(label, at: CGPoint(x: markX, y: min(markY + 7, chartHeight - 14)), anchor: .top)
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
                    with: .color(.primary.opacity(0.15)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
            }

            guard endX > 30, startX < width - 10 else { continue }
            let resolved = context.resolve(
                Text(verbatim: mark.label)
                    .font(dayFont)
                    .foregroundStyle(.primary.opacity(0.75))
            )
            let textWidth = resolved.measure(in: CGSize(width: 200, height: 20)).width
            let labelX = min(max(startX + 6, 6), endX - textWidth - 6)
            guard labelX + textWidth < width - 40 else { continue }
            context.draw(resolved, at: CGPoint(x: labelX, y: 5), anchor: .topLeading)
        }

        if nowX > 0, nowX < width {
            context.fill(
                Path(CGRect(x: nowX - 0.5, y: 0, width: 1, height: chartHeight)),
                with: .color(.primary.opacity(0.3))
            )
        }

        let unitFont = Font.system(size: 9, weight: .semibold)
        if let topLabel = layout.topLabel {
            let resolved = context.resolve(
                Text(verbatim: topLabel).font(unitFont).foregroundStyle(.primary.opacity(0.7))
            )
            context.draw(resolved, at: CGPoint(x: width - 6, y: 5), anchor: .topTrailing)
        }
        if let bottomLabel = layout.bottomLabel {
            let resolved = context.resolve(
                Text(verbatim: bottomLabel).font(unitFont).foregroundStyle(.primary.opacity(0.7))
            )
            context.draw(resolved, at: CGPoint(x: width - 6, y: chartHeight - 4), anchor: .bottomTrailing)
        }

        var calendar = Calendar.current
        calendar.timeZone = model.timeZone
        let tickFont = Font.system(size: 9, weight: .medium)
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
            if tickX > 10, tickX < width - 10, hour != 0,
               tickDate.timeIntervalSince1970 >= model.domain.lowerBound - 1_800,
               tickDate.timeIntervalSince1970 <= model.domain.upperBound + 1_800 {
                let label = context.resolve(
                    Text(verbatim: String(format: "%02d", hour))
                        .font(tickFont)
                        .foregroundStyle(.primary.opacity(0.55))
                )
                context.draw(label, at: CGPoint(x: tickX, y: chartHeight + Self.axisHeight / 2 + 2))
            }
            guard let next = calendar.date(byAdding: .hour, value: 6, to: tickDate) else { break }
            tickDate = next
        }

        // Playhead: pinned to the strip's center; the timeline moves beneath it.
        let headX = x(scrubTime)
        context.fill(
            Path(CGRect(x: headX - 0.75, y: 0, width: 1.5, height: chartHeight)),
            with: .color(.primary.opacity(0.85))
        )
        var headY: CGFloat?
        if layout.ridesBars {
            let rate = AtmosphereWeatherMapper.interpolatedValue(
                at: scrubTime, times: model.times, values: model.precipitation
            ) ?? 0
            headY = chartHeight - barHeight(rate)
        } else if let primary = layout.primary,
                  let value = AtmosphereWeatherMapper.interpolatedValue(
                      at: scrubTime, times: model.times, values: primary.values
                  ) {
            headY = yOf(value)
        }
        if let headY {
            let dot = Path(ellipseIn: CGRect(x: headX - 4.5, y: headY - 4.5, width: 9, height: 9))
            context.fill(dot, with: .color(Color(.systemBackground)))
            context.stroke(dot, with: .color(layout.primaryColor), lineWidth: 2)
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

/// Full-range overview under the strip: 14 days at a glance with the 48-hour
/// viewport box around the playhead. Dragging the box (or tapping elsewhere)
/// scrubs; the same grab-offset feel as the meteogram minimap.
struct HourlyTimelineMinimap: View {
    let model: HourlyTimelineModel

    @State private var grabOffset: Double?

    private static let chartHeight: CGFloat = 40
    private static let labelHeight: CGFloat = 13

    var body: some View {
        let scrubTime = model.scrubTime
        let layout = model.layout(for: model.lens)
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            Canvas { context, size in
                draw(context: &context, size: size, scrubTime: scrubTime, layout: layout)
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
        scrubTime: Double,
        layout: HourlyLensLayout
    ) {
        guard model.hasData else { return }
        let width = size.width
        let height = Self.chartHeight
        let domain = model.domain
        let seconds = max(domain.upperBound - domain.lowerBound, 1)

        func x(_ time: Double) -> CGFloat {
            CGFloat((time - domain.lowerBound) / seconds) * width
        }

        context.fill(
            Path(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: 6),
            with: .color(.primary.opacity(0.05))
        )

        for range in model.nightRanges {
            let x0 = max(0, x(range.lowerBound))
            let x1 = min(width, x(range.upperBound))
            guard x1 > x0 else { continue }
            context.fill(
                Path(CGRect(x: x0, y: 0, width: x1 - x0, height: height)),
                with: .color(.black.opacity(0.18))
            )
        }

        let times = model.times
        if layout.showsBars {
            let barWidth = max(1, width * CGFloat(7_200 / seconds))
            for (index, value) in model.precipitation.enumerated() where value > 0 {
                guard index < times.count else { break }
                let barH = max(1.5, CGFloat(value / model.precipitationMax) * (height * 0.45))
                context.fill(
                    Path(CGRect(x: x(times[index]) - barWidth / 2, y: height - barH, width: barWidth, height: barH)),
                    with: .color(.hourlyRain.opacity(0.8))
                )
            }
        }

        // Cloud lens: one total-cover ribbon instead of the three strip bands.
        if !layout.bands.isEmpty {
            let centerY = height * 0.45
            var top: [CGPoint] = []
            var bottom: [CGPoint] = []
            for index in stride(from: 0, to: min(times.count, model.cloudcover.count), by: 2) {
                let half = max(0.5, height * 0.3 * CGFloat(model.cloudcover[index] / 100))
                let pointX = x(times[index])
                top.append(CGPoint(x: pointX, y: centerY - half))
                bottom.append(CGPoint(x: pointX, y: centerY + half))
            }
            if top.count > 1 {
                var ribbon = Path()
                ribbon.move(to: top[0])
                for point in top.dropFirst() { ribbon.addLine(to: point) }
                for point in bottom.reversed() { ribbon.addLine(to: point) }
                ribbon.closeSubpath()
                context.fill(ribbon, with: .color(.hourlyCloud.opacity(0.8)))
            }
        }

        if let primary = layout.primary {
            let lensDomain = layout.domain
            let valueSpan = max(lensDomain.upperBound - lensDomain.lowerBound, 0.0001)
            var line = Path()
            var started = false
            for index in stride(from: 0, to: min(times.count, primary.values.count), by: 2) {
                let fraction = (primary.values[index] - lensDomain.lowerBound) / valueSpan
                let point = CGPoint(x: x(times[index]), y: height * (0.78 - 0.56 * CGFloat(fraction)))
                if started {
                    line.addLine(to: point)
                } else {
                    line.move(to: point)
                    started = true
                }
            }
            context.stroke(line, with: .color(layout.primaryColor), lineWidth: 1.25)
        }

        let labelFont = Font.system(size: 9, weight: .medium)
        let dayWidth = width * CGFloat(86_400 / seconds)
        for (index, mark) in model.dayMarks.enumerated() {
            let dayX = x(mark.start)
            if index > 0 {
                var rule = Path()
                rule.move(to: CGPoint(x: dayX, y: 0))
                rule.addLine(to: CGPoint(x: dayX, y: height))
                context.stroke(
                    rule,
                    with: .color(.primary.opacity(0.15)),
                    style: StrokeStyle(lineWidth: 0.75, dash: [2, 2.5])
                )
            }
            guard dayWidth > 30 || index % 2 == 0 else { continue }
            let label = context.resolve(
                Text(verbatim: mark.label).font(labelFont).foregroundStyle(.primary.opacity(0.65))
            )
            context.draw(label, at: CGPoint(x: dayX + 3, y: height + 2), anchor: .topLeading)
        }

        let nowX = x(Date.now.timeIntervalSince1970)
        if nowX > 0, nowX < width {
            context.fill(
                Path(CGRect(x: nowX - 0.5, y: 0, width: 1, height: height)),
                with: .color(.primary.opacity(0.35))
            )
        }

        let viewportRect = CGRect(
            x: x(scrubTime - model.windowSeconds / 2),
            y: 0.75,
            width: x(scrubTime + model.windowSeconds / 2) - x(scrubTime - model.windowSeconds / 2),
            height: height - 1.5
        )
        let viewport = Path(roundedRect: viewportRect, cornerRadius: 6)
        context.fill(viewport, with: .color(.primary.opacity(0.08)))
        context.stroke(viewport, with: .color(.primary.opacity(0.8)), lineWidth: 1.5)
    }
}
