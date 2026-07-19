import SwiftUI

/// Discrete zoom steps for the meteogram's visible x-window (pinch-driven).
enum MeteogramZoom: Int, CaseIterable, Identifiable {
  case hours24
  case hours36
  case days3
  case days7
  case days14

  var id: Int { rawValue }

  var seconds: TimeInterval {
    switch self {
    case .hours24: 86_400
    case .hours36: 129_600
    case .days3: 259_200
    case .days7: 604_800
    case .days14: 1_209_600
    }
  }

  /// Stride for per-hour glyph marks (weather icons, wind arrows).
  var glyphStrideHours: Int {
    switch self {
    case .hours24, .hours36: 6
    case .days3: 12
    case .days7: 24
    case .days14: 48
    }
  }

  /// Hour stride for axis labels; nil renders a day-level grid without hour labels.
  var hourAxisStride: Int? {
    switch self {
    case .hours24: 3
    case .hours36: 6
    case .days3: 12
    case .days7, .days14: nil
    }
  }
}

/// Immutable, fully precomputed data for the meteogram. The main canvas
/// merges daylight, clouds-by-altitude, temperature, and precipitation in a
/// meteoblue-style combined picture (0…1 unit y-space with zoned regions);
/// the wind strip below plots real values on its own fixed domain. Built once
/// per forecast — body re-evaluations during scrubbing never recompute.
struct MeteogramModel {
  struct Input {
    var time: [Double]
    var temperature: [Double]
    var precipitation: [Double]
    var snowfall: [Double]
    var precipitationProbability: [Double]
    var cloudcoverTotal: [Double]
    var cloudcoverLow: [Double]
    var cloudcoverMid: [Double]
    var cloudcoverHigh: [Double]
    var windspeed: [Double]
    var winddirection: [Double]
    var windgusts: [Double]
    var pressure: [Double]
    var weathercode: [Double]
    var isDay: [Double]
    var temperatureUnit: String
    var precipitationUnit: String
    var pressureUnit: String
    var windSpeedUnit: WindSpeedUnit
    var referenceDate: Date
  }

  /// Vertical zones of the main canvas in unit space (y up), meteoblue-style:
  /// icons on top, clouds at their altitude bands, temperature riding through
  /// the middle, precipitation anchored at the bottom.
  enum CanvasZone {
    static let iconRowY = 0.94
    static let cloudCenterLow = 0.58
    static let cloudCenterMid = 0.70
    static let cloudCenterHigh = 0.82
    /// Half of the center spacing: adjacent layers at 100 % cover touch and
    /// visually merge into one blob, meteoblue-style.
    static let cloudMaxHalfThickness = 0.06
    static let tempRange = 0.16...0.66
    static let precipTop = 0.14
  }

  struct CanvasPoint {
    let date: Date
    let tempY: Double
    let dayY: Double
    /// 1 where the sun is at least partly out (day, < 75 % cover).
    let sunPartlyY: Double
    /// 1 where the sky is mostly clear (day, < 35 % cover).
    let sunFullY: Double

    var zero: Double { 0 }
  }

  struct SeriesPoint {
    let date: Date
    let value: Double
  }

  struct BandPoint {
    let date: Date
    let yStart: Double
    let yEnd: Double
  }

  /// One cloud layer as a thickness-modulated ribbon at its altitude band.
  /// Thickness is the only encoding — it maps 1:1 to the reported cover.
  struct CloudRibbon: Identifiable {
    let id: Int
    let band: [BandPoint]
  }

  struct Glyph: Identifiable {
    let id: Int
    let date: Date
    let iconName: String
    let degrees: Double
    let isPast: Bool
  }

  struct PrecipBar: Identifiable {
    let id: Int
    let date: Date
    let snowTop: Double
    let rainTop: Double
    let isPast: Bool
  }

  struct ExtremumLabel: Identifiable {
    let id: Int
    let date: Date
    let y: Double
    let text: String
    let isMax: Bool
  }

  struct DayBoundary: Identifiable {
    let id: Int
    let date: Date
  }

  struct MinimapPoint {
    let frac: Double
    let tempFraction: Double
    let cloudFraction: Double
    let precipFraction: Double
  }

  struct MinimapDayMark: Identifiable {
    let id: Int
    let frac: Double
    let weekday: String
    let day: String
  }

  struct ReadoutValues {
    let date: Date
    let temperature: Double?
    let pressure: Double?
    let windSpeed: Double?
    let windDirection: Double?
    let gust: Double?
    let rain: Double?
    let snowfall: Double?
    let probability: Double?
    let cloudTotal: Double?
  }

  let dates: [Date]
  let fullRange: ClosedRange<Date>
  let referenceDate: Date
  let temperatureUnit: String
  let precipitationUnit: String
  let pressureUnit: String
  let windSpeedUnit: WindSpeedUnit

  // Main canvas (unit y-space).
  let canvasPoints: [CanvasPoint]
  let tempPast: [SeriesPoint]
  let tempFuture: [SeriesPoint]
  /// Pressure normalized into the temperature area on its own scale.
  let pressurePast: [SeriesPoint]
  let pressureFuture: [SeriesPoint]
  let hasPressure: Bool
  let cloudRibbons: [CloudRibbon]
  let precipBars: [PrecipBar]
  let extremaLabels: [ExtremumLabel]

  // Wind strip (real values).
  let windPast: [SeriesPoint]
  let windFuture: [SeriesPoint]
  let gustLine: [SeriesPoint]
  let gustBand: [BandPoint]
  let windDomain: ClosedRange<Double>

  let dayBoundaries: [DayBoundary]
  let availableZooms: [MeteogramZoom]

  let hasGusts: Bool
  let hasPrecipitation: Bool
  let temperatureMin: Double
  let temperatureMax: Double
  /// Unit-space y of the freezing level (0 °C / 32 °F) when it lies inside
  /// the temperature domain; nil otherwise.
  let freezingUnitY: Double?
  let freezingLabel: String
  /// Water-equivalent amount a full-height precipitation bar represents.
  let precipScaleMax: Double

  let minimapPoints: [MinimapPoint]
  let minimapDayMarks: [MinimapDayMark]
  let minimapNightRanges: [ClosedRange<Double>]

  /// Glyphs/axis values pre-filtered per zoom so chart bodies never allocate.
  private let iconsByStride: [Int: [Glyph]]
  private let arrowsByStride: [Int: [Glyph]]
  private let axisDatesByZoom: [MeteogramZoom: [Date]]

  private let epochs: [Double]
  private let temperature: [Double]
  private let tempUnitYs: [Double]
  private let pressure: [Double]
  private let windspeed: [Double]
  private let winddirection: [Double]
  private let windgusts: [Double]
  private let rainOnly: [Double]
  private let snowfall: [Double]
  private let probability: [Double]
  private let cloudTotal: [Double]

  init?(input: Input) {
    let count = min(input.time.count, input.temperature.count)
    guard count > 1 else { return nil }

    let epochs = Array(input.time.prefix(count))
    let dates = epochs.map { Date(timeIntervalSince1970: $0) }
    let temperature = Array(input.temperature.prefix(count))
    let referenceDate = input.referenceDate

    func aligned(_ values: [Double]) -> [Double] {
      values.count >= count ? Array(values.prefix(count)) : []
    }

    let windspeed = aligned(input.windspeed)
    let winddirection = aligned(input.winddirection)
    let windgusts = aligned(input.windgusts)
    let pressure = aligned(input.pressure)
    let precipitation = aligned(input.precipitation)
    let snowfall = aligned(input.snowfall)
    let probability = aligned(input.precipitationProbability)
    let cloudLow = aligned(input.cloudcoverLow)
    let cloudMid = aligned(input.cloudcoverMid)
    let cloudHigh = aligned(input.cloudcoverHigh)
    let weathercode = aligned(input.weathercode)
    let isDay = aligned(input.isDay)
    var cloudTotal = aligned(input.cloudcoverTotal)
    if cloudTotal.isEmpty && !cloudLow.isEmpty {
      cloudTotal = (0..<count).map { max(cloudLow[$0], max(cloudMid[$0], cloudHigh[$0])) }
    }

    self.dates = dates
    self.epochs = epochs
    self.fullRange = dates[0]...dates[count - 1]
    self.referenceDate = referenceDate
    self.temperatureUnit = input.temperatureUnit
    self.precipitationUnit = input.precipitationUnit
    self.pressureUnit = input.pressureUnit
    self.windSpeedUnit = input.windSpeedUnit
    self.temperature = temperature
    self.pressure = pressure
    self.windspeed = windspeed
    self.winddirection = winddirection
    self.windgusts = windgusts
    self.snowfall = snowfall
    self.probability = probability
    self.cloudTotal = cloudTotal
    self.hasGusts = !windgusts.isEmpty

    // MARK: Temperature zone (fixed over the full range so zooming never rescales)
    let rawMin = temperature.min() ?? 0
    let rawMax = temperature.max() ?? 1
    temperatureMin = rawMin
    temperatureMax = rawMax
    let tMin = ((rawMin - 2) / 5).rounded(.down) * 5
    let tMax = max(((rawMax + 2) / 5).rounded(.up) * 5, tMin + 5)
    func yTemp(_ v: Double) -> Double {
      CanvasZone.tempRange.lowerBound
        + (CanvasZone.tempRange.upperBound - CanvasZone.tempRange.lowerBound) * (v - tMin)
        / (tMax - tMin)
    }
    tempUnitYs = temperature.map(yTemp)

    let freezingPoint: Double = input.temperatureUnit.contains("F") ? 32 : 0
    if freezingPoint > tMin && freezingPoint < tMax {
      freezingUnitY = yTemp(freezingPoint)
    } else {
      freezingUnitY = nil
    }
    freezingLabel = "\(Int(freezingPoint))°"

    // MARK: Wind domain (strip; shared by line, arrows, and the gust band)
    let windPool = windspeed + windgusts
    let niceStep = Self.displayValue(fromKilometersPerHour: 10, unit: input.windSpeedUnit)
    let windFloor = Self.displayValue(fromKilometersPerHour: 20, unit: input.windSpeedUnit)
    let rawWindMax = max(windPool.max() ?? 0, windFloor)
    let wMax = max((rawWindMax / niceStep).rounded(.up) * niceStep, niceStep)
    windDomain = 0...wMax

    // MARK: Precipitation (sqrt into the bottom zone keeps drizzle visible)
    func snowWaterEquivalent(_ centimeters: Double) -> Double {
      let millimeters = centimeters * 10 / 7
      return input.precipitationUnit.lowercased() == "inch" ? millimeters / 25.4 : millimeters
    }
    var rainOnly = [Double](repeating: 0, count: count)
    var totalWater = [Double](repeating: 0, count: count)
    var snowWater = [Double](repeating: 0, count: count)
    for i in 0..<count {
      let precip = i < precipitation.count ? precipitation[i] : 0
      let snowWE = i < snowfall.count ? snowWaterEquivalent(max(0, snowfall[i])) : 0
      snowWater[i] = snowWE
      rainOnly[i] = max(0, precip - snowWE)
      totalWater[i] = max(precip, snowWE)
    }
    self.rainOnly = rainOnly
    let referenceMax = input.precipitationUnit.lowercased() == "inch" ? 0.08 : 2.0
    let pMax = max(referenceMax, totalWater.max() ?? 0)
    precipScaleMax = pMax
    func yBarTop(_ waterEquivalent: Double) -> Double {
      CanvasZone.precipTop * (min(waterEquivalent, pMax) / pMax).squareRoot()
    }
    hasPrecipitation = totalWater.contains { $0 > 0 }

    // MARK: Canvas points (temperature, daylight, and sunshine columns)
    var canvasPoints: [CanvasPoint] = []
    canvasPoints.reserveCapacity(count)
    for i in 0..<count {
      let day = (i < isDay.count ? isDay[i] : 0) > 0
      let cover = i < cloudTotal.count ? cloudTotal[i] : 100
      canvasPoints.append(
        CanvasPoint(
          date: dates[i],
          tempY: tempUnitYs[i],
          dayY: day ? 1 : 0,
          sunPartlyY: day && cover < 75 ? 1 : 0,
          sunFullY: day && cover < 35 ? 1 : 0
        ))
    }
    self.canvasPoints = canvasPoints

    func splitSeries(_ values: [Double], transform: (Double) -> Double = { $0 })
      -> (past: [SeriesPoint], future: [SeriesPoint])
    {
      guard !values.isEmpty else { return ([], []) }
      var past: [SeriesPoint] = []
      var future: [SeriesPoint] = []
      for i in 0..<min(count, values.count) {
        let point = SeriesPoint(date: dates[i], value: transform(values[i]))
        if dates[i] <= referenceDate { past.append(point) }
        if dates[i] >= referenceDate { future.append(point) }
      }
      return (past, future)
    }
    (tempPast, tempFuture) = splitSeries(temperature, transform: yTemp)
    (windPast, windFuture) = splitSeries(windspeed)

    // Pressure shares the temperature area on its own scale (nice 5-unit pad).
    hasPressure = !pressure.isEmpty
    if let pressureMin = pressure.min(), let pressureMax = pressure.max() {
      let lower = ((pressureMin - 2) / 5).rounded(.down) * 5
      let upper = max(((pressureMax + 2) / 5).rounded(.up) * 5, lower + 10)
      func yPressure(_ v: Double) -> Double {
        CanvasZone.tempRange.lowerBound
          + (CanvasZone.tempRange.upperBound - CanvasZone.tempRange.lowerBound) * (v - lower)
          / (upper - lower)
      }
      (pressurePast, pressureFuture) = splitSeries(pressure, transform: yPressure)
    } else {
      (pressurePast, pressureFuture) = ([], [])
    }

    if !windgusts.isEmpty && !windspeed.isEmpty {
      let gustCount = min(count, min(windgusts.count, windspeed.count))
      gustLine = (0..<gustCount).map { SeriesPoint(date: dates[$0], value: windgusts[$0]) }
      gustBand = (0..<gustCount).map {
        BandPoint(
          date: dates[$0], yStart: windspeed[$0], yEnd: max(windspeed[$0], windgusts[$0]))
      }
    } else {
      gustLine = []
      gustBand = []
    }

    // MARK: Cloud ribbons at altitude bands (2 h downsample for smoothness)
    func ribbon(id: Int, center: Double, cover: [Double], maxHalf: Double) -> CloudRibbon {
      var band: [BandPoint] = []
      for i in Swift.stride(from: 0, to: min(count, cover.count), by: 2) {
        let half = maxHalf * cover[i] / 100
        band.append(BandPoint(date: dates[i], yStart: center - half, yEnd: center + half))
      }
      return CloudRibbon(id: id, band: band)
    }
    if !cloudLow.isEmpty && !cloudMid.isEmpty && !cloudHigh.isEmpty {
      cloudRibbons = [
        ribbon(
          id: 0, center: CanvasZone.cloudCenterLow, cover: cloudLow,
          maxHalf: CanvasZone.cloudMaxHalfThickness),
        ribbon(
          id: 1, center: CanvasZone.cloudCenterMid, cover: cloudMid,
          maxHalf: CanvasZone.cloudMaxHalfThickness),
        ribbon(
          id: 2, center: CanvasZone.cloudCenterHigh, cover: cloudHigh,
          maxHalf: CanvasZone.cloudMaxHalfThickness),
      ]
    } else if !cloudTotal.isEmpty {
      cloudRibbons = [
        ribbon(
          id: 0, center: CanvasZone.cloudCenterMid, cover: cloudTotal,
          maxHalf: CanvasZone.cloudMaxHalfThickness * 3)
      ]
    } else {
      cloudRibbons = []
    }

    // MARK: Precipitation bars (wet hours only, snow stacked under rain)
    var bars: [PrecipBar] = []
    for i in 0..<count where totalWater[i] > 0 {
      let total = yBarTop(totalWater[i])
      let snowShare = snowWater[i] / max(totalWater[i], .leastNonzeroMagnitude)
      bars.append(
        PrecipBar(
          id: i,
          date: dates[i],
          snowTop: total * min(1, snowShare),
          rainTop: total,
          isPast: dates[i] < referenceDate
        ))
    }
    precipBars = bars

    // MARK: Weather icons + wind arrows, pre-filtered per zoom stride
    var icons: [Glyph] = []
    for i in 0..<min(count, weathercode.count) {
      icons.append(
        Glyph(
          id: i,
          date: dates[i],
          iconName: HourlyFormatting.weatherIconName(
            weatherCode: weathercode[i], isDay: i < isDay.count ? isDay[i] : 1),
          degrees: 0,
          isPast: dates[i] < referenceDate
        ))
    }
    var arrows: [Glyph] = []
    for i in 0..<min(count, winddirection.count) {
      arrows.append(
        Glyph(
          id: i,
          date: dates[i],
          iconName: "location.north.fill",
          degrees: (winddirection[i] + 180).truncatingRemainder(dividingBy: 360),
          isPast: dates[i] < referenceDate
        ))
    }
    let strides = Set(MeteogramZoom.allCases.map(\.glyphStrideHours))
    iconsByStride = strides.reduce(into: [:]) { result, stride in
      // Offset by half a stride so icons sit between the axis gridlines.
      result[stride] = icons.filter { ($0.id + stride / 2) % stride == 0 }
    }
    arrowsByStride = strides.reduce(into: [:]) { result, stride in
      result[stride] = arrows.filter { $0.id % stride == 0 }
    }

    // MARK: Daily temperature extrema labels (inline, meteoblue-style)
    var labels: [ExtremumLabel] = []
    let calendar = Calendar.current
    var dayStart = 0
    var labelID = 0
    for i in 1...count {
      let dayEnded = i == count || !calendar.isDate(dates[i - 1], inSameDayAs: dates[i])
      guard dayEnded else { continue }
      let indices = dayStart..<i
      defer { dayStart = i }
      guard indices.count >= 6 else { continue }
      let maxIndex = indices.max(by: { temperature[$0] < temperature[$1] })!
      let minIndex = indices.min(by: { temperature[$0] < temperature[$1] })!
      labels.append(
        ExtremumLabel(
          id: labelID, date: dates[maxIndex], y: tempUnitYs[maxIndex],
          text: "\(Int(temperature[maxIndex].rounded()))°", isMax: true))
      labelID += 1
      if minIndex != maxIndex {
        labels.append(
          ExtremumLabel(
            id: labelID, date: dates[minIndex], y: tempUnitYs[minIndex],
            text: "\(Int(temperature[minIndex].rounded()))°", isMax: false))
        labelID += 1
      }
    }
    // Boundary artifacts: same-kind labels closer than 4 h keep only the more extreme one.
    labels.sort { $0.date < $1.date }
    var deduped: [ExtremumLabel] = []
    for label in labels {
      if let last = deduped.last, last.isMax == label.isMax,
        label.date.timeIntervalSince(last.date) < 4 * 3600
      {
        let lastValue = Double(last.text.dropLast()) ?? 0
        let value = Double(label.text.dropLast()) ?? 0
        let keepNew = label.isMax ? value > lastValue : value < lastValue
        if keepNew { deduped[deduped.count - 1] = label }
      } else {
        deduped.append(label)
      }
    }
    extremaLabels = deduped

    // MARK: Day boundaries
    dayBoundaries = HourlyChartUtilities.dayChangeIndices(time: epochs).enumerated().map {
      offset, index in
      DayBoundary(id: offset, date: dates[index])
    }

    // MARK: Zoom steps clamped to the actual domain (Spain/Portugal ships 7-day hourly)
    let domainSeconds = epochs[count - 1] - epochs[0]
    let fitting = MeteogramZoom.allCases.filter { $0.seconds <= domainSeconds + 3600 }
    availableZooms = fitting.isEmpty ? [.hours24] : fitting

    // MARK: Axis tick dates per zoom (hour marks, or midnights for day-level zooms)
    let hours = dates.map { calendar.component(.hour, from: $0) }
    let midnights = HourlyChartUtilities.dayChangeIndices(time: epochs).map { dates[$0] }
    axisDatesByZoom = MeteogramZoom.allCases.reduce(into: [:]) { result, zoom in
      if let stride = zoom.hourAxisStride {
        result[zoom] = (0..<count).filter { hours[$0] % stride == 0 }.map { dates[$0] }
      } else {
        result[zoom] = midnights
      }
    }

    // MARK: Minimap downsample (2 h step) in domain-fraction space
    let total = max(domainSeconds, 1)
    let tempSpan = max(tMax - tMin, 1)
    var miniPoints: [MinimapPoint] = []
    for i in Swift.stride(from: 0, to: count, by: 2) {
      miniPoints.append(
        MinimapPoint(
          frac: (epochs[i] - epochs[0]) / total,
          tempFraction: (temperature[i] - tMin) / tempSpan,
          cloudFraction: i < cloudTotal.count ? cloudTotal[i] / 100 : 0,
          precipFraction: (min(totalWater[i], pMax) / pMax).squareRoot()
        ))
    }
    minimapPoints = miniPoints
    minimapDayMarks = dayBoundaries.map { boundary in
      MinimapDayMark(
        id: boundary.id,
        frac: (boundary.date.timeIntervalSince1970 - epochs[0]) / total,
        weekday: HourlyChartUtilities.dayAbbreviation(from: boundary.date).uppercased(),
        day: boundary.date.formatted(.dateTime.day())
      )
    }
    var nightRanges: [ClosedRange<Double>] = []
    var nightStart: Int?
    for i in 0...count {
      let night = i < count && i < isDay.count && isDay[i] <= 0
      if night, nightStart == nil {
        nightStart = i
      } else if !night, let start = nightStart {
        nightRanges.append(
          ((epochs[start] - epochs[0]) / total)...((epochs[max(start, i - 1)] - epochs[0]) / total))
        nightStart = nil
      }
    }
    minimapNightRanges = nightRanges
  }

  // MARK: - Lookup

  var domainSeconds: TimeInterval {
    fullRange.upperBound.timeIntervalSince(fullRange.lowerBound)
  }

  func weatherIcons(for zoom: MeteogramZoom) -> [Glyph] {
    iconsByStride[zoom.glyphStrideHours] ?? []
  }

  func arrows(for zoom: MeteogramZoom) -> [Glyph] {
    arrowsByStride[zoom.glyphStrideHours] ?? []
  }

  func axisDates(for zoom: MeteogramZoom) -> [Date] {
    axisDatesByZoom[zoom] ?? []
  }

  /// Fixed y-position for the wind-direction arrow row near the strip top.
  var arrowRowY: Double {
    windDomain.upperBound * 0.9
  }

  /// Nearest hourly index for a raw selection date (binary search).
  func snappedIndex(for date: Date) -> Int {
    let target = date.timeIntervalSince1970
    var low = 0
    var high = epochs.count - 1
    while low < high {
      let mid = (low + high) / 2
      if epochs[mid] < target { low = mid + 1 } else { high = mid }
    }
    if low > 0, abs(epochs[low - 1] - target) <= abs(epochs[low] - target) {
      return low - 1
    }
    return low
  }

  var currentIndex: Int {
    snappedIndex(for: referenceDate)
  }

  func values(at index: Int) -> ReadoutValues {
    func value(_ array: [Double], _ i: Int) -> Double? {
      array.indices.contains(i) ? array[i] : nil
    }
    return ReadoutValues(
      date: dates.indices.contains(index) ? dates[index] : referenceDate,
      temperature: value(temperature, index),
      pressure: value(pressure, index),
      windSpeed: value(windspeed, index),
      windDirection: value(winddirection, index),
      gust: value(windgusts, index),
      rain: value(rainOnly, index),
      snowfall: value(snowfall, index),
      probability: value(probability, index),
      cloudTotal: value(cloudTotal, index)
    )
  }

  /// Unit-space y of the temperature curve (for canvas dots).
  func temperatureUnitY(at index: Int) -> Double? {
    tempUnitYs.indices.contains(index) ? tempUnitYs[index] : nil
  }

  func windValue(at index: Int) -> Double? {
    windspeed.indices.contains(index) ? windspeed[index] : nil
  }

  // MARK: - Helpers

  private static func displayValue(fromKilometersPerHour value: Double, unit: WindSpeedUnit)
    -> Double
  {
    switch unit {
    case .kmh: value
    case .ms: value / 3.6
    case .mph: value / 1.609344
    case .kn: value / 1.852
    case .bft: Double(BeaufortScale.force(forKilometersPerHour: value))
    }
  }
}
