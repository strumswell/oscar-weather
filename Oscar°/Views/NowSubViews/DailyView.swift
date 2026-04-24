import SwiftUI

struct DailyView: View {
  @Environment(Weather.self) private var weather: Weather

  var body: some View {
    // Cap at 12 days to keep View from getting too large with too much (unreliable) data
    let showsPlaceholders = shouldShowPlaceholders
    let dayNumber = showsPlaceholders ? placeholderDayCount : dailyDisplayCount
    let temperatureScale = displayedTemperatureScale
    let heading = String.localizedStringWithFormat(
      NSLocalizedString("%d-Tage", comment: "Headline for Daily View"), dayNumber)
    let temperatureUnit = weather.forecast.daily_units?.temperature_2m_min ?? "°C"
    let precipitationUnit = weather.forecast.daily_units?.precipitation_sum ?? "mm"

    VStack(alignment: .leading) {
      Text(heading)
        .font(.title3)
        .bold()
        .foregroundColor(Color(UIColor.label))
        .padding([.leading, .top, .bottom])

      VStack {
        if showsPlaceholders {
          ForEach(0..<placeholderDayCount, id: \.self) { _ in
            DailyPlaceholderRow()
              .redacted(reason: .placeholder)
          }
        } else {
          ForEach(Array(0..<dayNumber), id: \.self) { dayPos in
            let dayMinTemp = weather.forecast.daily?.temperature_2m_min?[dayPos] ?? 0
            let dayMaxTemp = weather.forecast.daily?.temperature_2m_max?[dayPos] ?? 0
            HStack {
              Text(getWeekDay(timestamp: weather.forecast.daily?.time[dayPos] ?? 0.0))
                .foregroundColor(Color(UIColor.label))
                .bold()
                .frame(width: 45, alignment: .leading)
              Image(getWeatherIcon(pos: dayPos))
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
              VStack {
                Text(
                  "\(weather.forecast.daily?.precipitation_sum?[dayPos] ?? 0, specifier: "%.1f") \(precipitationUnit)"
                )
                .font(.caption)
                .foregroundColor(Color(UIColor.label))
                .contentTransition(.numericText())
              }
              .frame(width: 50)
              Text(roundTemperatureString(temperature: dayMinTemp))
                .frame(width: 37, alignment: .trailing)
                .contentTransition(.numericText())
              TemperatureRangeView(
                low: dayMinTemp, high: dayMaxTemp,
                minTemp: temperatureScale.min, maxTemp: temperatureScale.max,
                unit: temperatureUnit
              )
              .frame(height: 5)
              Text(roundTemperatureString(temperature: dayMaxTemp))
                .frame(width: 37, alignment: .leading)
                .contentTransition(.numericText())
            }
            .padding(.vertical, 4)
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 10)
      .background(.thinMaterial)
      .cornerRadius(10)
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(Color(UIColor(.secondary.opacity(0.075))), lineWidth: 1)
      )
      .font(.system(size: 18))
      .padding([.leading, .trailing])
      .opacity(weather.isLoading ? 0.3 : 1.0)
      .animation(.easeInOut(duration: 0.3), value: weather.isLoading)

    }
    .scrollTransition { content, phase in
      content
        .opacity(phase.isIdentity ? 1 : 0.8)
        .scaleEffect(phase.isIdentity ? 1 : 0.99)
        .blur(radius: phase.isIdentity ? 0 : 0.5)
    }
  }
}

extension DailyView {
  private var placeholderDayCount: Int {
    12
  }

  private var shouldShowPlaceholders: Bool {
    weather.isLoading && dailyDisplayCount == 0
  }

  private var dailyDisplayCount: Int {
    guard let daily = weather.forecast.daily else {
      return 0
    }

    let availableCount = [
      daily.time.count,
      daily.weathercode?.count ?? 0,
      daily.precipitation_sum?.count ?? 0,
      daily.temperature_2m_min?.count ?? 0,
      daily.temperature_2m_max?.count ?? 0
    ].min() ?? 0

    return min(availableCount, 12)
  }

  private var displayedTemperatureScale: (min: Double, max: Double) {
    let displayedMinimums = Array(weather.forecast.daily?.temperature_2m_min?.prefix(dailyDisplayCount) ?? [])
    let displayedMaximums = Array(weather.forecast.daily?.temperature_2m_max?.prefix(dailyDisplayCount) ?? [])
    let allTemperatures = displayedMinimums + displayedMaximums
    let minTemp = allTemperatures.min() ?? 0
    let maxTemp = allTemperatures.max() ?? 40

    return (minTemp, maxTemp)
  }

  public func getWeekDay(timestamp: Double) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.timeZone =
      TimeZone(secondsFromGMT: weather.forecast.utc_offset_seconds ?? 0) ?? TimeZone.current
    dateFormatter.dateFormat = "E"
    return dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
  }

  public func getWeatherIcon(pos: Int) -> String {
    switch weather.forecast.daily?.weathercode?[pos] ?? 0 {
    case 0, 1:
      return "01d"
    case 2:
      return "02d"
    case 3:
      return "04d"
    case 45, 48:
      return "50d"
    case 51:
      return "10d"
    case 71, 73, 75, 77, 85, 86:
      return "13d"
    case 95, 96, 99:
      return "11d"
    default:
      return "09d"
    }
  }
}

private struct DailyPlaceholderRow: View {
  var body: some View {
    HStack {
      RoundedRectangle(cornerRadius: 3)
        .frame(width: 35, height: 15)
        .frame(width: 45, alignment: .leading)
      Circle()
        .frame(width: 30, height: 30)
      RoundedRectangle(cornerRadius: 3)
        .frame(width: 42, height: 12)
        .frame(width: 50)
      RoundedRectangle(cornerRadius: 3)
        .frame(width: 25, height: 15)
        .frame(width: 37, alignment: .trailing)
      Capsule()
        .frame(height: 5)
      RoundedRectangle(cornerRadius: 3)
        .frame(width: 25, height: 15)
        .frame(width: 37, alignment: .leading)
    }
    .foregroundStyle(.secondary.opacity(0.28))
    .padding(.vertical, 4)
    .accessibilityHidden(true)
  }
}

struct TemperatureRangeView: View {
  let low: Double
  let high: Double
  let minTemp: Double
  let maxTemp: Double
  let unit: String

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      let lowPosition = position(for: min(low, high), in: width)
      let highPosition = position(for: max(low, high), in: width)
      let selectedWidth = maxTemp == minTemp ? width : max(highPosition - lowPosition, 0)

      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.gray.opacity(0.3))
          .frame(width: width, height: 4)
        globalGradient
          .frame(width: width, height: 4)
          .mask(alignment: .leading) {
            Capsule()
              .frame(width: selectedWidth, height: 4)
              .offset(x: lowPosition)
          }
      }
      .alignmentGuide(VerticalAlignment.center) { d in d[VerticalAlignment.center] }
    }
  }

  private var globalGradient: LinearGradient {
    LinearGradient(
      stops: gradientStops(),
      startPoint: .leading,
      endPoint: .trailing
    )
  }

  func position(for temperature: Double, in width: CGFloat) -> CGFloat {
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

  func color(for temperature: Double, unit: String) -> Color {
    switch unit {
    case "°C":
      return colorForCelsius(temperature)
    case "°F":
      return colorForFahrenheit(temperature)
    case "K":
      return colorForKelvin(temperature)
    default:
      return colorForCelsius(temperature)  // Default to Celsius if unit is unknown
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
