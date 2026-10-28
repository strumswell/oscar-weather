import Foundation

enum HourlyForecastBuilder {
  static func makeItems(
    forecast: Operations.getForecast.Output.Ok.Body.jsonPayload,
    precipSeries: PrecipSeriesResponse? = nil,
    units: Units,
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

    let timeZone = forecast.locationTimeZone
    let sunEvents = SunEventIndex(daily: forecast.daily, timeZone: timeZone)

    if let current = forecast.current,
       let firstFutureIndex = hourly.time.firstIndex(where: { $0 > current.time }),
       firstFutureIndex < availableCount {
      var items: [HourlyTimelineItem] = [
        .forecast(nowItem(current: current, precipSeries: precipSeries, units: units))
      ]

      if !isLoading, firstFutureIndex > 0,
         let sunEvent = sunEvents.item(forHourAt: hourly.time[firstFutureIndex - 1]),
         sunEvent.timestamp > current.time {
        items.append(.sunEvent(sunEvent))
      }

      items += hourlyItems(
        range: firstFutureIndex...min(firstFutureIndex + 47, availableCount - 1),
        hourly: hourly,
        units: units,
        timeZone: timeZone,
        sunEvents: sunEvents,
        isLoading: isLoading
      )
      return items
    }

    let startIndex = min(localizedHourIndex(currentTime: forecast.current?.time, hours: hourly.time), availableCount - 1)
    return hourlyItems(
      range: startIndex...min(startIndex + 48, availableCount - 1),
      hourly: hourly,
      units: units,
      timeZone: timeZone,
      sunEvents: sunEvents,
      isLoading: isLoading
    )
  }

  private static func hourlyItems(
    range: ClosedRange<Int>,
    hourly: Operations.getForecast.Output.Ok.Body.jsonPayload.hourlyPayload,
    units: Units,
    timeZone: TimeZone,
    sunEvents: SunEventIndex,
    isLoading: Bool
  ) -> [HourlyTimelineItem] {
    var items: [HourlyTimelineItem] = []
    for index in range {
      let timestamp = hourly.time[index]
      let forecastItem = HourlyForecastItem(
        timestamp: timestamp,
        hour: HourlyFormatting.hourString(timestamp: timestamp, timeZone: timeZone),
        precipitation: units.precipitationString(hourly.precipitation?[index] ?? 0),
        iconName: HourlyFormatting.weatherIconName(
          weatherCode: hourly.weathercode?[index] ?? 0,
          isDay: hourly.is_day?[index] ?? 0
        ),
        temperature: units.temperatureString(hourly.temperature_2m?[index]),
        precipitationValue: hourly.precipitation?[index] ?? 0
      )

      items.append(.forecast(forecastItem))

      if !isLoading, let sunEvent = sunEvents.item(forHourAt: timestamp) {
        items.append(.sunEvent(sunEvent))
      }
    }

    return items
  }

  private static func nowItem(
    current: Components.Schemas.CurrentWeather,
    precipSeries: PrecipSeriesResponse?,
    units: Units
  ) -> HourlyForecastItem {
    let precipitation = precipSeries?.currentRate ?? current.precipitation ?? 0

    var weatherCode = current.weathercode
    if precipitation > 0, weatherCode < 51 {
      weatherCode = precipitation >= 2.5 ? 61 : 51
    }

    return HourlyForecastItem(
      timestamp: current.time,
      hour: String(localized: "Jetzt"),
      precipitation: units.precipitationString(precipitation),
      iconName: HourlyFormatting.weatherIconName(
        weatherCode: weatherCode,
        isDay: current.is_day ?? 1
      ),
      temperature: units.temperatureString(current.temperature),
      isNow: true,
      precipitationValue: precipitation
    )
  }

  static func hasHourlyDetailData(forecast: Operations.getForecast.Output.Ok.Body.jsonPayload) -> Bool {
    !(forecast.hourly?.time.isEmpty ?? true)
  }

  private static func localizedHourIndex(currentTime: Double?, hours: [Double]) -> Int {
    guard let currentTime else { return 0 }
    return hours.indices.min { abs(currentTime - hours[$0]) < abs(currentTime - hours[$1]) } ?? 0
  }

  private struct SunEventIndex {
    private var byDay: [Double: (sunrise: Double?, sunset: Double?)] = [:]
    private var calendar: Calendar

    init(daily: Components.Schemas.DailyResponse?, timeZone: TimeZone) {
      calendar = Calendar.current
      calendar.timeZone = timeZone
      let sunrises = daily?.sunrise ?? []
      let sunsets = daily?.sunset ?? []
      for (index, sunrise) in sunrises.enumerated() {
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: sunrise)).timeIntervalSince1970
        byDay[day] = (sunrise, sunsets.indices.contains(index) ? sunsets[index] : nil)
      }
    }

    func item(forHourAt hourlyTimestamp: Double) -> HourlySunEventItem? {
      let hourDate = Date(timeIntervalSince1970: hourlyTimestamp)
      guard let events = byDay[calendar.startOfDay(for: hourDate).timeIntervalSince1970] else { return nil }
      let hour = calendar.component(.hour, from: hourDate)
      if let sunrise = events.sunrise,
         calendar.component(.hour, from: Date(timeIntervalSince1970: sunrise)) == hour {
        return HourlySunEventItem(
          kind: .sunrise,
          timestamp: sunrise,
          time: HourlyFormatting.timeString(timestamp: sunrise, timeZone: calendar.timeZone),
          weekday: HourlyFormatting.weekdayString(timestamp: sunrise, timeZone: calendar.timeZone)
        )
      }
      if let sunset = events.sunset,
         calendar.component(.hour, from: Date(timeIntervalSince1970: sunset)) == hour {
        return HourlySunEventItem(
          kind: .sunset,
          timestamp: sunset,
          time: HourlyFormatting.timeString(timestamp: sunset, timeZone: calendar.timeZone),
          weekday: HourlyFormatting.weekdayString(timestamp: sunset, timeZone: calendar.timeZone)
        )
      }
      return nil
    }
  }
}
