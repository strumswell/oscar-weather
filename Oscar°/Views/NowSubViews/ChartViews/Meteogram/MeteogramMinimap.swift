import SwiftUI

/// Full-range overview strip under the meteogram: a Canvas rendering of the
/// downsampled forecast with a draggable viewport that drives the synced panel
/// group via normalized offsets. Canvas instead of a fifth Chart — at this
/// height features are 1–3 px and a mark pipeline would be pure overhead.
struct MeteogramMinimap: View {
  let model: MeteogramModel
  /// 0 = window at domain start, 1 = window at domain end.
  let normalizedOffset: CGFloat
  let visibleSeconds: TimeInterval
  let onScrub: (CGFloat) -> Void

  @State private var grabOffsetFraction: Double?
  @State private var wasClamped = false

  private static let chartHeight: CGFloat = 52
  private static let labelHeight: CGFloat = 16

  private var domainSeconds: TimeInterval {
    max(model.domainSeconds, 1)
  }

  /// Viewport width as a fraction of the whole domain.
  private var visibleFraction: Double {
    min(visibleSeconds / domainSeconds, 1)
  }

  /// Viewport start as a fraction of the whole domain.
  private var startFraction: Double {
    Double(normalizedOffset) * (1 - visibleFraction)
  }

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      ZStack(alignment: .topLeading) {
        canvas
        viewport(width: width)
      }
      .contentShape(.rect)
      .gesture(dragGesture(width: width))
    }
    .frame(height: Self.chartHeight + Self.labelHeight)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Übersicht"))
    .accessibilityValue(Text(verbatim: accessibilityRangeDescription))
    .accessibilityAdjustableAction { direction in
      let scrollable = max(domainSeconds - visibleSeconds, 1)
      let dayStep = CGFloat(86_400 / scrollable)
      let delta = direction == .increment ? dayStep : -dayStep
      onScrub(min(max(normalizedOffset + delta, 0), 1))
    }
  }

  // MARK: - Rendering

  private var canvas: some View {
    Canvas { context, size in
      let width = size.width
      let chartHeight = Self.chartHeight

      var background = Path(
        roundedRect: CGRect(x: 0, y: 0, width: width, height: chartHeight), cornerRadius: 6)
      context.fill(background, with: .color(.white.opacity(0.06)))

      for range in model.minimapNightRanges {
        let x0 = range.lowerBound * width
        let x1 = max(range.upperBound * width, x0 + 1)
        background = Path(CGRect(x: x0, y: 0, width: x1 - x0, height: chartHeight))
        context.fill(background, with: .color(.black.opacity(0.25)))
      }

      let points = model.minimapPoints
      guard points.count > 1 else { return }

      // Cloud ribbon along the top, thickness by total cover.
      let cloudCenter: CGFloat = 8
      var cloudPath = Path()
      let topEdge = points.map { point in
        CGPoint(x: point.frac * width, y: cloudCenter - (0.5 + point.cloudFraction * 4.5))
      }
      let bottomEdge = points.reversed().map { point in
        CGPoint(x: point.frac * width, y: cloudCenter + (0.5 + point.cloudFraction * 4.5))
      }
      cloudPath.addLines(topEdge + bottomEdge)
      cloudPath.closeSubpath()
      context.fill(cloudPath, with: .color(.white.opacity(0.45)))

      // Precipitation bars from the bottom.
      let barWidth = max(1, width * CGFloat(7200 / domainSeconds) * 0.7)
      for point in points where point.precipFraction > 0 {
        let barHeight = max(1.5, point.precipFraction * 16)
        let bar = Path(
          CGRect(
            x: point.frac * width - barWidth / 2, y: chartHeight - barHeight,
            width: barWidth, height: barHeight))
        context.fill(bar, with: .color(.blue.opacity(0.8)))
      }

      // Temperature polyline in the middle band.
      var tempPath = Path()
      tempPath.addLines(
        points.map {
          CGPoint(x: $0.frac * width, y: chartHeight * (0.72 - 0.52 * $0.tempFraction))
        })
      context.stroke(tempPath, with: .color(.orange), lineWidth: 1.5)

      // Day ticks + collision-filtered labels.
      let dayWidth = width * CGFloat(86_400 / domainSeconds)
      let dropDayNumber = dayWidth < 34
      let labelStride = dayWidth < 20 ? 2 : 1
      for mark in model.minimapDayMarks {
        let x = mark.frac * width
        var tick = Path()
        tick.move(to: CGPoint(x: x, y: 0))
        tick.addLine(to: CGPoint(x: x, y: chartHeight))
        context.stroke(tick, with: .color(.white.opacity(0.18)), lineWidth: 1)

        guard mark.id % labelStride == 0 else { continue }
        let labelText = dropDayNumber ? mark.weekday : "\(mark.weekday) \(mark.day)"
        let label = context.resolve(
          Text(verbatim: labelText)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.55)))
        context.draw(label, at: CGPoint(x: x + 3, y: chartHeight + 3), anchor: .topLeading)
      }
    }
  }

  private func viewport(width: CGFloat) -> some View {
    let viewportWidth = max(8, width * CGFloat(visibleFraction))
    let x = width * CGFloat(startFraction)
    return RoundedRectangle(cornerRadius: 6)
      .fill(.white.opacity(0.1))
      .strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
      .frame(width: viewportWidth, height: Self.chartHeight)
      .offset(x: min(max(0, x), max(0, width - viewportWidth)))
  }

  // MARK: - Interaction

  private func dragGesture(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let touchFraction = Double(min(max(0, value.location.x / max(width, 1)), 1))

        if grabOffsetFraction == nil {
          let start = startFraction
          let end = start + visibleFraction
          let initialTouch = Double(min(max(0, value.startLocation.x / max(width, 1)), 1))
          if initialTouch >= start && initialTouch <= end {
            grabOffsetFraction = initialTouch - start
          } else {
            // Touch outside the viewport: center it there, then keep dragging.
            grabOffsetFraction = visibleFraction / 2
          }
        }

        let scrollableFraction = max(1 - visibleFraction, .leastNonzeroMagnitude)
        // 30-minute steps so drags don't force chart layouts per gesture sample.
        let quantum = 1800 / domainSeconds
        let targetStart = ((touchFraction - (grabOffsetFraction ?? 0)) / quantum).rounded()
          * quantum
        let clampedStart = min(max(0, targetStart), 1 - visibleFraction)
        if clampedStart != targetStart, !wasClamped {
          UIApplication.shared.playHapticFeedback()
        }
        wasClamped = clampedStart != targetStart

        let target = CGFloat(clampedStart / scrollableFraction)
        guard abs(target - normalizedOffset) > 0.0005 else { return }
        onScrub(min(max(target, 0), 1))
      }
      .onEnded { _ in
        grabOffsetFraction = nil
        wasClamped = false
      }
  }

  private var accessibilityRangeDescription: String {
    let start = model.fullRange.lowerBound.addingTimeInterval(
      startFraction * domainSeconds)
    let end = start.addingTimeInterval(visibleSeconds)
    return start.formatted(.dateTime.weekday(.wide).day())
      + " – " + end.formatted(.dateTime.weekday(.wide).day())
  }
}
