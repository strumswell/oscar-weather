import SwiftUI

/// The day rail at the sheet's bottom: 14 days at a glance — white
/// temperature line, precipitation ticks — with the 48-hour viewport box
/// around the playhead. Lens-independent: the rail is navigation, not data
/// display. Dragging the box (or tapping elsewhere) scrubs; the same
/// grab-offset feel.
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
