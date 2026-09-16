import Foundation

enum HourlyForecastBuilder {
  static func makeItems(
    forecast: Operations.getForecast.Output.Ok.Body.jsonPayload,
    precipSeries: PrecipSeriesResponse? = nil,
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
    let precipitationUnit = forecast.hourly_units?.precipitation ?? "mm"
    let sunEvents = SunEventIndex(daily: forecast.daily, timeZone: timeZone)

    // "Jetzt" replaces the current hour: a card with the live conditions —
    // radar-aware precipitation and icon — followed by the whole hours strictly
    // after now.
    if let current = forecast.current,
       let firstFutureIndex = hourly.time.firstIndex(where: { $0 > current.time }),
       firstFutureIndex < availableCount {
      var items: [HourlyTimelineItem] = [
        .forecast(nowItem(current: current, precipSeries: precipSeries, precipitationUnit: precipitationUnit))
      ]

      // A sunrise/sunset between now and the first whole hour lives in the hour
      // slot the Jetzt card replaces — carry it over instead of dropping it.
      if !isLoading, firstFutureIndex > 0,
         let sunEvent = sunEvents.item(forHourAt: hourly.time[firstFutureIndex - 1]),
         sunEvent.timestamp > current.time {
        items.append(.sunEvent(sunEvent))
      }

      items += hourlyItems(
        range: firstFutureIndex...min(firstFutureIndex + 47, availableCount - 1),
        hourly: hourly,
        precipitationUnit: precipitationUnit,
        timeZone: timeZone,
        sunEvents: sunEvents,
        isLoading: isLoading
      )
      return items
    }

    // No usable current conditions (or the forecast is exhausted): the plain
    // hourly strip starting at the hour nearest to now.
    let startIndex = min(localizedHourIndex(currentTime: forecast.current?.time, hours: hourly.time), availableCount - 1)
    return hourlyItems(
      range: startIndex...min(startIndex + 48, availableCount - 1),
      hourly: hourly,
      precipitationUnit: precipitationUnit,
      timeZone: timeZone,
      sunEvents: sunEvents,
      isLoading: isLoading
    )
  }

  private static func hourlyItems(
    range: ClosedRange<Int>,
    hourly: Operations.getForecast.Output.Ok.Body.jsonPayload.hourlyPayload,
    precipitationUnit: String,
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
        precipitation: HourlyFormatting.precipitationString(
          value: hourly.precipitation?[index] ?? 0,
          unit: precipitationUnit
        ),
        iconName: HourlyFormatting.weatherIconName(
          weatherCode: hourly.weathercode?[index] ?? 0,
          isDay: hourly.is_day?[index] ?? 0
        ),
        temperature: HourlyFormatting.temperatureString(hourly.temperature_2m?[index]),
        precipitationValue: hourly.precipitation?[index] ?? 0
      )

      items.append(.forecast(forecastItem))

      if !isLoading, let sunEvent = sunEvents.item(forHourAt: timestamp) {
        items.append(.sunEvent(sunEvent))
      }
    }

    return items
  }

  /// The "Jetzt" card: current conditions, with radar overriding the model where
  /// it has fresh coverage — radar measures what is falling right now, while the
  /// model's "current" precipitation is an interpolated guess.
  private static func nowItem(
    current: Components.Schemas.CurrentWeather,
    precipSeries: PrecipSeriesResponse?,
    precipitationUnit: String
  ) -> HourlyForecastItem {
    let radarRate = precipSeries?.currentRate
    let forecastPrecipitation = current.precipitation ?? 0
    let precipitation = radarRate.map { precipitationValue(fromMillimeters: $0, unit: precipitationUnit) }
      ?? forecastPrecipitation
    let isRaining = (radarRate ?? forecastPrecipitation) > 0

    // Lift a dry-sky code to a precipitation icon when rain is actually reaching
    // the ground (mirrors the widgets' radar-aware icon). A code that already
    // shows precipitation keeps its more specific icon (snow, thunderstorm, …).
    var weatherCode = current.weathercode
    if isRaining, weatherCode < 51 {
      weatherCode = (radarRate ?? forecastPrecipitation) >= 2.5 ? 61 : 51
    }

    return HourlyForecastItem(
      timestamp: current.time,
      hour: String(localized: "Jetzt"),
      precipitation: HourlyFormatting.precipitationString(
        value: precipitation,
        unit: precipitationUnit
      ),
      iconName: HourlyFormatting.weatherIconName(
        weatherCode: weatherCode,
        isDay: current.is_day ?? 1
      ),
      temperature: HourlyFormatting.temperatureString(current.temperature),
      isNow: true,
      precipitationValue: precipitation
    )
  }

  /// Radar rates are always mm/h; the card label follows the user's unit setting.
  private static func precipitationValue(fromMillimeters value: Double, unit: String) -> Double {
    unit.lowercased() == "inch" ? value / 25.4 : value
  }

  static func hasHourlyDetailData(forecast: Operations.getForecast.Output.Ok.Body.jsonPayload) -> Bool {
    !(forecast.hourly?.time.isEmpty ?? true)
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

  /// Sunrise and sunset per local day, built once per item list so the
  /// per-hour lookup is a dictionary hit instead of a calendar scan.
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
