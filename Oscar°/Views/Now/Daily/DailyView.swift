import SwiftUI

struct DailyView: View {
  @Environment(Weather.self) private var weather: Weather
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(NowPresentationCoordinator.self) private var presentation
  private let settingsService = SettingService.shared
  @State private var detailPresentationCount = 0

  // Column widths scale with Dynamic Type so the weekday and temperature labels keep their
  // alignment without truncating at larger accessibility text sizes.
  @ScaledMetric private var weekdayColumnWidth: CGFloat = 45
  @ScaledMetric private var precipitationColumnWidth: CGFloat = 50
  @ScaledMetric private var temperatureColumnWidth: CGFloat = 37
  @ScaledMetric private var dayIconSize: CGFloat = 30

  var body: some View {
    // Cap at 12 days to keep View from getting too large with too much (unreliable) data
    let showsPlaceholders = shouldShowPlaceholders
    let dayNumber = showsPlaceholders ? placeholderDayCount : dailyDisplayCount
    let temperatureScale = displayedTemperatureScale
    let heading = String.localizedStringWithFormat(
      NSLocalizedString("%d-Tage", comment: "Headline for Daily View"), dayNumber)
    let temperatureUnit = weather.forecast.daily_units?.temperature_2m_min ?? "°C"
    let precipitationUnit = weather.forecast.daily_units?.precipitation_sum ?? "mm"

    Group {
      VStack(alignment: .leading) {
        Text(heading)
          .font(.title3)
          .bold()
          .foregroundStyle(Color(UIColor.label))
          .padding([.leading, .top, .bottom])

        VStack {
          if showsPlaceholders {
            ForEach(0..<placeholderDayCount, id: \.self) { _ in
              DailyPlaceholderRow()
                .redacted(reason: .placeholder)
            }
          } else {
            ForEach(Array(0..<dayNumber), id: \.self) { dayPos in
              let rowTemperatures = temperatureRow(for: dayPos)
              HStack {
                Text(getWeekDay(timestamp: weather.forecast.daily?.time[dayPos] ?? 0.0))
                  .foregroundStyle(Color(UIColor.label))
                  .bold()
                  .frame(width: weekdayColumnWidth, alignment: .leading)
                Image(getWeatherIcon(pos: dayPos))
                  .resizable()
                  .scaledToFit()
                  .frame(width: dayIconSize, height: dayIconSize)
                VStack {
                  Text(
                    "\(weather.forecast.daily?.precipitation_sum?[dayPos] ?? 0, specifier: "%.1f") \(precipitationUnit)"
                  )
                  .font(.caption)
                  .foregroundStyle(Color(UIColor.label))
                }
                .frame(width: precipitationColumnWidth)
                Text(roundTemperatureString(temperature: rowTemperatures.labelLow))
                  .frame(width: temperatureColumnWidth, alignment: .trailing)
                TemperatureRangeView(
                  low: rowTemperatures.barLow, high: rowTemperatures.barHigh,
                  focusLow: rowTemperatures.focusLow,
                  focusHigh: rowTemperatures.focusHigh,
                  minTemp: temperatureScale.min, maxTemp: temperatureScale.max,
                  unit: temperatureUnit
                )
                .frame(height: rowTemperatures.focusLow == nil ? 5 : 28)
                Text(roundTemperatureString(temperature: rowTemperatures.labelHigh))
                  .frame(width: temperatureColumnWidth, alignment: .leading)
              }
              .padding(.vertical, 4)
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .cardBackground()
        .clipShape(.rect(cornerRadius: 10))
        .cardBorder()
        .font(.body)
        .padding([.leading, .trailing])

      }
    }
    .contentShape(.rect)
    .onTapGesture(perform: presentDetails)
    .disabled(!hasDailyDetailData)
    .accessibilityAction(named: Text("Tägliche Details"), presentDetails)
    .accessibilityIdentifier("now.daily")
    .scrollTransition { [reduceMotion] content, phase in
      content
        .opacity(phase.isIdentity ? 1 : 0.8)
        .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.99)
    }
    .sensoryFeedback(.impact, trigger: detailPresentationCount)
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

  private var hasDailyDetailData: Bool {
    dailyDisplayCount > 0
  }

  private var displayedTemperatureScale: (min: Double, max: Double) {
    let rowTemperatures = (0..<dailyDisplayCount).map { temperatureRow(for: $0) }
    let allTemperatures = rowTemperatures.flatMap { row in
      [
        row.barLow,
        row.barHigh,
        row.focusLow,
        row.focusHigh
      ].compactMap { $0 }
    }
    let minTemp = allTemperatures.min() ?? 0
    let maxTemp = allTemperatures.max() ?? 40

    return (minTemp, maxTemp)
  }

  private func temperatureRow(for dayIndex: Int) -> DailyTemperatureRow {
    let dailyLow = dailyTemperature(weather.forecast.daily?.temperature_2m_min, at: dayIndex) ?? 0
    let dailyHigh = dailyTemperature(weather.forecast.daily?.temperature_2m_max, at: dayIndex) ?? 0

    guard settingsService.dailyForecastDaytimeTemperaturesEnabled else {
      return DailyTemperatureRow.dailyOnly(low: dailyLow, high: dailyHigh)
    }

    guard let timeframeTemperatures = timeframeTemperatures(for: dayIndex) else {
      return DailyTemperatureRow.dailyOnly(low: dailyLow, high: dailyHigh)
    }

    switch settingsService.dailyForecastDaytimeTemperatureDisplayMode {
    case .replaceValues:
      return DailyTemperatureRow.dailyOnly(
        low: timeframeTemperatures.low,
        high: timeframeTemperatures.high
      )
    case .overlayOnDailyRange:
      return DailyTemperatureRow(
        labelLow: dailyLow,
        labelHigh: dailyHigh,
        barLow: dailyLow,
        barHigh: dailyHigh,
        focusLow: timeframeTemperatures.low,
        focusHigh: timeframeTemperatures.high
      )
    }
  }

  private func timeframeTemperatures(for dayIndex: Int) -> (low: Double, high: Double)? {
    guard let hourlyTimes = weather.forecast.hourly?.time,
          let hourlyTemperatures = weather.forecast.hourly?.temperature_2m,
          let interval = daytimeTemperatureInterval(for: dayIndex) else {
      return nil
    }

    let intervalTemperatures = zip(hourlyTimes, hourlyTemperatures)
      .compactMap { timestamp, temperature -> Double? in
        guard timestamp >= interval.start && timestamp <= interval.end else { return nil }
        return temperature
      }

    guard let low = intervalTemperatures.min(),
          let high = intervalTemperatures.max() else {
      return nil
    }

    return (low, high)
  }

  private func daytimeTemperatureInterval(for dayIndex: Int) -> (start: Double, end: Double)? {
    switch settingsService.dailyForecastDaytimeTemperatureRangeMode {
    case .sunriseSunset:
      guard let sunrise = dailyTemperature(weather.forecast.daily?.sunrise, at: dayIndex),
            let sunset = dailyTemperature(weather.forecast.daily?.sunset, at: dayIndex),
            sunrise <= sunset else {
        return nil
      }

      return (sunrise, sunset)
    case .customHours:
      guard let dayTimestamp = dailyTemperature(weather.forecast.daily?.time, at: dayIndex) else {
        return nil
      }

      let timeZone = TimeZone(secondsFromGMT: weather.forecast.utc_offset_seconds ?? 0) ?? .current
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = timeZone

      let dayDate = Date(timeIntervalSince1970: TimeInterval(dayTimestamp))
      let startHour = settingsService.dailyForecastDaytimeCustomStartHour
      let endHour = settingsService.dailyForecastDaytimeCustomEndHour

      guard let startDate = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: dayDate),
            let endDate = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: dayDate),
            startDate <= endDate else {
        return nil
      }

      return (startDate.timeIntervalSince1970, endDate.timeIntervalSince1970)
    }
  }

  private func dailyTemperature(_ values: [Double]?, at index: Int) -> Double? {
    guard let values, values.indices.contains(index) else {
      return nil
    }

    return values[index]
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

  private func presentDetails() {
    guard hasDailyDetailData else { return }
    detailPresentationCount += 1
    presentation.present(.daily)
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
