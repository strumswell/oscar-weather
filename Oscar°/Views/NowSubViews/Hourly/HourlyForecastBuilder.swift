import Foundation

enum HourlyForecastBuilder {
  static func makeItems(
    forecast: Operations.getForecast.Output.Ok.Body.jsonPayload,
    isLoading: Bool
  ) -> [HourlyTimelineItem] {
    guard let hourly = forecast.hourly else {
      return []
    }

    let availableCount = [
      hourly.time.count,
      hourly.precipitation?.count ?? 0,
      hourly.weathercode?.count ?? 0,
      hourly.is_day?.count ?? 0,
      hourly.temperature_2m?.count ?? 0
    ].min() ?? 0

    guard availableCount > 0 else {
      return []
    }

    let timeZone = TimeZone(secondsFromGMT: forecast.utc_offset_seconds ?? 0) ?? .current
    let startIndex = min(localizedHourIndex(currentTime: forecast.current?.time, hours: hourly.time), availableCount - 1)
    let endIndex = min(startIndex + 48, availableCount - 1)
    let precipitationUnit = forecast.hourly_units?.precipitation ?? "mm"

    var items: [HourlyTimelineItem] = []
    for index in startIndex...endIndex {
      let timestamp = hourly.time[index]
      let forecastItem = HourlyForecastItem(
        timestamp: timestamp,
        hour: HourlyFormatting.hourString(timestamp: timestamp, timeZone: timeZone),
        precipitation: HourlyFormatting.precipitationString(
          value: hourly.precipitation?[index] ?? 0,
          unit: precipitationUnit
        ),
        iconName: HourlyFormatting.weatherIconName(
          weatherCode: hourly.weathercode?[index] ?? 0,
          isDay: hourly.is_day?[index] ?? 0
        ),
        temperature: HourlyFormatting.temperatureString(hourly.temperature_2m?[index])
      )

      items.append(.forecast(forecastItem))

      if !isLoading,
         let sunEvent = sunEventItem(
           for: timestamp,
           daily: forecast.daily,
           timeZone: timeZone
         ) {
        items.append(.sunEvent(sunEvent))
      }
    }

    return items
  }

  static func hasHourlyDetailData(forecast: Operations.getForecast.Output.Ok.Body.jsonPayload, isLoading: Bool) -> Bool {
    !isLoading && !(forecast.hourly?.time.isEmpty ?? true)
  }

  private static func localizedHourIndex(currentTime: Double?, hours: [Double]) -> Int {
    guard let currentTime,
          !hours.isEmpty
    else {
      return 0
    }

    var closestTime = Double.greatestFiniteMagnitude
    var closestIndex = 0

    for (index, time) in hours.enumerated() {
      let difference = abs(currentTime - time)
      if difference < closestTime {
        closestTime = difference
        closestIndex = index
      }
    }

    return closestIndex
  }

  private static func sunEventItem(
    for hourlyTimestamp: Double,
    daily: Components.Schemas.DailyResponse?,
    timeZone: TimeZone
  ) -> HourlySunEventItem? {
    guard let daily,
          let sunrise = daily.sunrise,
          let sunset = daily.sunset,
          let dayIndex = dayIndex(for: hourlyTimestamp, sunrise: sunrise, timeZone: timeZone)
    else {
      return nil
    }

    if sunrise.indices.contains(dayIndex),
       isWithinSameHour(hourlyTimestamp, sunrise[dayIndex], timeZone: timeZone) {
      return HourlySunEventItem(
        kind: .sunrise,
        timestamp: sunrise[dayIndex],
        time: HourlyFormatting.timeString(timestamp: sunrise[dayIndex], timeZone: timeZone),
        weekday: HourlyFormatting.weekdayString(timestamp: sunrise[dayIndex], timeZone: timeZone)
      )
    }

    if sunset.indices.contains(dayIndex),
       isWithinSameHour(hourlyTimestamp, sunset[dayIndex], timeZone: timeZone) {
      return HourlySunEventItem(
        kind: .sunset,
        timestamp: sunset[dayIndex],
        time: HourlyFormatting.timeString(timestamp: sunset[dayIndex], timeZone: timeZone),
        weekday: HourlyFormatting.weekdayString(timestamp: sunset[dayIndex], timeZone: timeZone)
      )
    }

    return nil
  }

  private static func dayIndex(for hourlyTimestamp: Double, sunrise: [Double], timeZone: TimeZone) -> Int? {
    let hourlyDate = Date(timeIntervalSince1970: TimeInterval(hourlyTimestamp))
    var calendar = Calendar.current
    calendar.timeZone = timeZone

    for (index, sunriseTimestamp) in sunrise.enumerated() {
      let sunriseDate = Date(timeIntervalSince1970: TimeInterval(sunriseTimestamp))
      if calendar.isDate(hourlyDate, inSameDayAs: sunriseDate) {
        return index
      }
    }

    return nil
  }

  private static func isWithinSameHour(_ firstTimestamp: Double, _ secondTimestamp: Double, timeZone: TimeZone) -> Bool {
    let firstDate = Date(timeIntervalSince1970: TimeInterval(firstTimestamp))
    let secondDate = Date(timeIntervalSince1970: TimeInterval(secondTimestamp))
    var calendar = Calendar.current
    calendar.timeZone = timeZone

    return calendar.component(.hour, from: firstDate) == calendar.component(.hour, from: secondDate)
  }
}
