import SwiftUI

struct HourlyTimelineStrip: View {
    let model: HourlyTimelineModel
    let lens: HourlyLens

    @State private var isDragging = false
    @State private var readoutSize: CGSize = .zero
    @State private var readoutOnLeft = false

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
                    },
                isEnabled: model.dayWindow == nil
            )
            .overlay(alignment: .topLeading) {
                if model.dayWindow == nil {
                    HourlyReadoutBox(model: model, layout: layout)
                        .onGeometryChange(for: CGSize.self, of: { $0.size }) { readoutSize = $0 }
                        .offset(x: readoutX(width: width), y: 22)
                        .animation(.snappy(duration: 0.25), value: readoutOnLeft)
                        .allowsHitTesting(false)
                }
            }
        }
        .onChange(of: model.scrubTime) { old, new in
            if new != old { readoutOnLeft = new > old }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.3), trigger: model.hourTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Zeitleiste"))
        .accessibilityValue(Text(verbatim: model.accessibilityValue))
        .accessibilityAdjustableAction { direction in
            model.nudge(hours: direction == .increment ? 1 : -1)
        }
    }

    private func readoutX(width: CGFloat) -> CGFloat {
        readoutOnLeft ? max(width / 2 - 10 - readoutSize.width, 2) : width / 2 + 10
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
        let showsDay = model.dayWindow != nil

        let firstTime = model.domain.lowerBound
        let firstIndex = max(0, Int((windowStart - firstTime) / 3_600) - 1)
        let lastIndex = min(model.times.count - 1, firstIndex + Int(windowSeconds / 3_600) + 2)
        guard firstIndex <= lastIndex else { return }

        let domain = showsDay ? Self.dayDomain(layout, indices: firstIndex...lastIndex) : layout.domain
        let span = max(domain.upperBound - domain.lowerBound, 0.0001)
        func yOf(_ value: Double) -> CGFloat {
            let fraction = (value - domain.lowerBound) / span
            return chartHeight * (0.84 - 0.58 * CGFloat(fraction))
        }
        func barHeight(_ value: Double) -> CGFloat {
            max(2, CGFloat(value / model.precipitationMax) * chartHeight * 0.5)
        }

        func splitStroke(_ path: Path, color: Color, lineWidth: CGFloat) {
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            if nowX > 0 {
                var past = context
                past.clip(to: Path(CGRect(x: 0, y: 0, width: min(nowX, width), height: size.height)))
                past.stroke(path, with: .color(color.opacity(0.45)), style: style)
            }
            if nowX < width {
                var future = context
                future.clip(to: Path(CGRect(x: max(nowX, 0), y: 0, width: width - max(nowX, 0), height: size.height)))
                future.stroke(path, with: .color(color), style: style)
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

        let hourWidth = width * CGFloat(3_600 / windowSeconds)
        let currentHour = Int((nowTime - firstTime) / 3_600)
        if showsDay, model.times.indices.contains(currentHour) {
            let columnX = x(model.times[currentHour]) - hourWidth / 2
            context.fill(
                Path(roundedRect: CGRect(x: columnX, y: 0, width: hourWidth, height: chartHeight), cornerRadius: 4),
                with: .color(.white.opacity(0.1))
            )
        }

        var labelRects: [CGRect] = []

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

            var labelContext = context
            labelContext.addFilter(.shadow(color: .black.opacity(0.35), radius: 1.5))
            let label = labelContext.resolve(
                Text(verbatim: band.label)
                    .font(.caption2.weight(.medium))
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
            splitStroke(path, color: line.color, lineWidth: line.width)
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

        if showsDay, lens == .overview {
            let iconSize = min(20, hourWidth - 3)
            var icons: [String: GraphicsContext.ResolvedImage] = [:]
            for index in firstIndex...lastIndex where index < model.weathercode.count {
                let iconX = x(model.times[index])
                guard iconX - iconSize / 2 >= 0, iconX + iconSize / 2 <= width else { continue }
                let lineTop = layout.lines
                    .filter { index < $0.values.count }
                    .map { yOf($0.values[index]) }
                    .min() ?? chartHeight / 2
                let isDay = index < model.isDay.count ? model.isDay[index] : 1
                let name = HourlyFormatting.weatherIconName(weatherCode: model.weathercode[index], isDay: isDay)
                let icon = icons[name] ?? context.resolve(Image(name))
                icons[name] = icon
                let rect = CGRect(x: iconX - iconSize / 2, y: max(lineTop - 6 - iconSize, 2), width: iconSize, height: iconSize)
                var iconContext = context
                iconContext.opacity = index < currentHour ? 0.45 : 1
                iconContext.draw(icon, in: rect)
                labelRects.append(rect)
            }
        }

        if !showsDay {
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
        let tickHours = showsDay ? 3 : 6
        components.hour = ((components.hour ?? 0) / tickHours) * tickHours
        components.minute = 0
        var tickDate = calendar.date(from: components) ?? Date(timeIntervalSince1970: windowStart)
        var guardCounter = 0
        while tickDate.timeIntervalSince1970 < windowStart + windowSeconds, guardCounter < 16 {
            guardCounter += 1
            let tickX = x(tickDate.timeIntervalSince1970)
            let hour = calendar.component(.hour, from: tickDate)
            let inData = tickDate.timeIntervalSince1970 >= model.domain.lowerBound - 1_800
                && tickDate.timeIntervalSince1970 <= model.domain.upperBound + 1_800
            if inData {
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
            guard let next = calendar.date(byAdding: .hour, value: tickHours, to: tickDate) else { break }
            tickDate = next
        }

        let headX = x(scrubTime)
        context.fill(
            Path(CGRect(x: headX - 0.75, y: 0, width: 1.5, height: chartHeight)),
            with: .color(.white.opacity(0.95))
        )
        func interpolated(_ values: [Double]) -> Double? {
            AtmosphereWeatherMapper.interpolatedValue(at: scrubTime, times: model.times, values: values)
        }

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

    private static func dayDomain(_ layout: HourlyLensLayout, indices: ClosedRange<Int>) -> ClosedRange<Double> {
        let values = layout.lines.flatMap { line in
            indices.filter { $0 < line.values.count }.map { line.values[$0] }
        }
        guard let low = values.min(), let high = values.max() else { return layout.domain }
        let pad = max((high - low) * 0.1, (layout.domain.upperBound - layout.domain.lowerBound) * 0.05)
        let lower = layout.domain.lowerBound == 0 ? 0 : low - pad
        return lower...(high + pad)
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
