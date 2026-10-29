import SwiftUI

struct TemperatureRangeView: View {
  let low: Double
  let high: Double
  let focusLow: Double?
  let focusHigh: Double?
  let minTemp: Double
  let maxTemp: Double
  let unit: TemperatureUnit
  @ScaledMetric(relativeTo: .caption2) var labelGlyphWidth: CGFloat = 6

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      let lowPosition = position(for: min(low, high), in: width)
      let highPosition = position(for: max(low, high), in: width)
      let selectedWidth = maxTemp == minTemp ? width : max(highPosition - lowPosition, 0)
      let showsFocus = focusLow != nil && focusHigh != nil
      let barYOffset: CGFloat = showsFocus ? 18 : 0
      let focusLowValue = focusLow.map { min($0, focusHigh ?? $0) }
      let focusHighValue = focusHigh.map { max($0, focusLow ?? $0) }
      let focusLowPosition = focusLowValue.map { position(for: $0, in: width) }
      let focusHighPosition = focusHighValue.map { position(for: $0, in: width) }
      let focusWidth = focusLowPosition.flatMap { lowPosition in
        focusHighPosition.map { max($0 - lowPosition, 0) }
      }

      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.gray.opacity(0.3))
          .frame(width: width, height: 4)
          .offset(y: barYOffset)
        globalGradient
          .frame(width: width, height: 4)
          .opacity(focusLowValue == nil ? 1 : 0.28)
          .mask(alignment: .leading) {
            Capsule()
              .frame(width: selectedWidth, height: 4)
              .offset(x: lowPosition)
          }
          .offset(y: barYOffset)
        if let focusLowValue,
           let focusHighValue,
           let focusLowPosition,
           let focusHighPosition,
           let focusWidth {
          globalGradient
            .frame(width: width, height: 5)
            .mask(alignment: .leading) {
              Capsule()
                .frame(width: max(focusWidth, 4), height: 5)
                .offset(x: focusLowPosition)
            }
            .offset(y: barYOffset)

          let labelOffsets = separatedLabelOffsets(
            lowPosition: focusLowPosition,
            highPosition: focusHighPosition,
            width: width,
            minGap: labelGap(focusLowValue, focusHighValue),
            separate: shouldShowFocusMarker(for: focusLowValue)
              && shouldShowFocusMarker(for: focusHighValue)
              && focusLowValue != focusHighValue
          )

          if shouldShowFocusMarker(for: focusLowValue) {
            focusMarker(
              temperature: focusLowValue,
              xPosition: focusLowPosition,
              labelOffset: labelOffsets.low,
              availableWidth: width,
              barYOffset: barYOffset
            )
            .zIndex(focusLowValue == focusHighValue ? 0 : 1)
          }

          if shouldShowFocusMarker(for: focusHighValue) {
            focusMarker(
              temperature: focusHighValue,
              xPosition: focusHighPosition,
              labelOffset: labelOffsets.high,
              availableWidth: width,
              barYOffset: barYOffset
            )
            .zIndex(2)
          }
        }
      }
      .alignmentGuide(VerticalAlignment.center) { d in d[VerticalAlignment.center] }
    }
  }

  private static let focusLabelWidth: CGFloat = 28

  private func focusMarker(
    temperature: Double,
    xPosition: CGFloat,
    labelOffset: CGFloat,
    availableWidth: CGFloat,
    barYOffset: CGFloat
  ) -> some View {
    let dotSize: CGFloat = 8
    let dotOffset = min(max(xPosition - dotSize / 2, 0), max(availableWidth - dotSize, 0))

    return ZStack(alignment: .leading) {
      Text(unit.string(temperature))
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(Color.primary)
        .frame(width: Self.focusLabelWidth)
        .offset(x: labelOffset, y: 1)

      Circle()
        .fill(.white)
        .frame(width: dotSize, height: dotSize)
        .overlay(
          Circle()
            .stroke(Color.black.opacity(0.75), lineWidth: 0.8)
        )
        .offset(x: dotOffset, y: barYOffset)
    }
  }

  private func separatedLabelOffsets(
    lowPosition: CGFloat,
    highPosition: CGFloat,
    width: CGFloat,
    minGap: CGFloat,
    separate: Bool
  ) -> (low: CGFloat, high: CGFloat) {
    let maxOffset = max(width - Self.focusLabelWidth, 0)
    func centered(_ x: CGFloat) -> CGFloat {
      min(max(x - Self.focusLabelWidth / 2, 0), maxOffset)
    }

    let low = centered(lowPosition)
    let high = centered(highPosition)
    guard separate, high - low < minGap else {
      return (low, high)
    }

    let mid = (low + high) / 2
    var newLow = mid - minGap / 2
    var newHigh = mid + minGap / 2
    if newLow < 0 {
      newHigh -= newLow
      newLow = 0
    }
    if newHigh > maxOffset {
      newLow -= (newHigh - maxOffset)
      newHigh = maxOffset
    }
    return (max(newLow, 0), newHigh)
  }

  private func labelGap(_ low: Double, _ high: Double) -> CGFloat {
    let glyphs = unit.string(low).count + unit.string(high).count
    return min(CGFloat(glyphs) * labelGlyphWidth / 2 + 3, Self.focusLabelWidth + 2)
  }

  private func shouldShowFocusMarker(for temperature: Double) -> Bool {
    let roundedTemperature = unit.rounded(temperature)
    return roundedTemperature != unit.rounded(low) && roundedTemperature != unit.rounded(high)
  }

  private var globalGradient: LinearGradient {
    LinearGradient(
      stops: gradientStops(),
      startPoint: .leading,
      endPoint: .trailing
    )
  }

  private func position(for temperature: Double, in width: CGFloat) -> CGFloat {
    let range = maxTemp - minTemp
    guard range > 0 else {
      return temperature <= minTemp ? 0 : width
    }

    let scale = ((temperature - minTemp) / range).clamped(to: 0...1)
    return CGFloat(scale) * width
  }

  private func gradientStops() -> [Gradient.Stop] {
    let range = maxTemp - minTemp

    guard range > 0 else {
      return [
        .init(color: color(for: minTemp), location: 0),
        .init(color: color(for: minTemp), location: 1)
      ]
    }

    var stops: [Gradient.Stop] = [
      .init(color: color(for: minTemp), location: 0)
    ]

    for threshold in Self.thresholds where threshold > minTemp && threshold < maxTemp {
      let location = (threshold - minTemp) / range
      stops.append(.init(color: color(for: threshold), location: location))
    }

    stops.append(.init(color: color(for: maxTemp), location: 1))
    return stops
  }

  private static let thresholds: [Double] = [0, 10, 20, 30]
  private static let bands: [Color] = [.blue, .green, .yellow, .orange, .red]

  private func color(for temperature: Double) -> Color {
    Self.bands[Self.thresholds.filter { temperature >= $0 }.count]
  }
}

extension Double {
  fileprivate func clamped(to limits: ClosedRange<Self>) -> Self {
    min(max(self, limits.lowerBound), limits.upperBound)
  }
}
