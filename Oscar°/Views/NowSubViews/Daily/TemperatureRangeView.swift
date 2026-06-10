import SwiftUI

struct TemperatureRangeView: View {
  let low: Double
  let high: Double
  let focusLow: Double?
  let focusHigh: Double?
  let minTemp: Double
  let maxTemp: Double
  let unit: String

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

          if shouldShowFocusMarker(for: focusLowValue) {
            focusMarker(
              temperature: focusLowValue,
              xPosition: focusLowPosition,
              availableWidth: width,
              barYOffset: barYOffset
            )
            .zIndex(focusLowValue == focusHighValue ? 0 : 1)
          }

          if shouldShowFocusMarker(for: focusHighValue) {
            focusMarker(
              temperature: focusHighValue,
              xPosition: focusHighPosition,
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

  private func focusMarker(
    temperature: Double,
    xPosition: CGFloat,
    availableWidth: CGFloat,
    barYOffset: CGFloat
  ) -> some View {
    let dotSize: CGFloat = 8
    let labelWidth: CGFloat = 28
    let dotOffset = min(max(xPosition - dotSize / 2, 0), max(availableWidth - dotSize, 0))
    let labelOffset = min(max(xPosition - labelWidth / 2, 0), max(availableWidth - labelWidth, 0))

    return ZStack(alignment: .leading) {
      Text(roundTemperatureString(temperature: temperature))
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(Color(UIColor.label))
        .frame(width: labelWidth)
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

  private func shouldShowFocusMarker(for temperature: Double) -> Bool {
    let roundedTemperature = roundedDisplayTemperature(temperature)
    return roundedTemperature != roundedDisplayTemperature(low)
      && roundedTemperature != roundedDisplayTemperature(high)
  }

  private func roundedDisplayTemperature(_ temperature: Double) -> Int {
    Int(temperature.rounded())
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
    let thresholds = temperatureThresholds(for: unit)
    let range = maxTemp - minTemp

    guard range > 0 else {
      return [
        .init(color: color(for: minTemp, unit: unit), location: 0),
        .init(color: color(for: minTemp, unit: unit), location: 1)
      ]
    }

    var stops: [Gradient.Stop] = [
      .init(color: color(for: minTemp, unit: unit), location: 0)
    ]

    for threshold in thresholds where threshold > minTemp && threshold < maxTemp {
      let location = (threshold - minTemp) / range
      stops.append(.init(color: color(for: threshold, unit: unit), location: location))
    }

    stops.append(.init(color: color(for: maxTemp, unit: unit), location: 1))
    return stops
  }

  private func temperatureThresholds(for unit: String) -> [Double] {
    switch unit {
    case "°F":
      return [32, 50, 68, 86]
    case "K":
      return [273, 283, 293, 303]
    default:
      return [0, 10, 20, 30]
    }
  }

  private func color(for temperature: Double, unit: String) -> Color {
    switch unit {
    case "°C":
      return colorForCelsius(temperature)
    case "°F":
      return colorForFahrenheit(temperature)
    case "K":
      return colorForKelvin(temperature)
    default:
      return colorForCelsius(temperature)
    }
  }

  private func colorForCelsius(_ temperature: Double) -> Color {
    switch temperature {
    case ..<0:
      return .blue
    case 0..<10:
      return .green
    case 10..<20:
      return .yellow
    case 20..<30:
      return .orange
    case 30...:
      return .red
    default:
      return .purple
    }
  }

  private func colorForFahrenheit(_ temperature: Double) -> Color {
    switch temperature {
    case ..<32:
      return .blue
    case 32..<50:
      return .green
    case 50..<68:
      return .yellow
    case 68..<86:
      return .orange
    case 86...:
      return .red
    default:
      return .purple
    }
  }

  private func colorForKelvin(_ temperature: Double) -> Color {
    switch temperature {
    case ..<273:
      return .blue
    case 273..<283:
      return .green
    case 283..<293:
      return .yellow
    case 293..<303:
      return .orange
    case 303...:
      return .red
    default:
      return .purple
    }
  }
}

extension Double {
  fileprivate func clamped(to limits: ClosedRange<Self>) -> Self {
    min(max(self, limits.lowerBound), limits.upperBound)
  }
}
