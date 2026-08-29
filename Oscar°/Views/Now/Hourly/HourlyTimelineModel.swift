import SwiftUI
import UIKit

/// Scrub clock + timeline data for the hourly detail sheet. The stage, HUD,
/// and strip observe one instance, so a drag anywhere moves all of them.
/// Glides run on a ~60 Hz ticker task owned by the model.
@MainActor
@Observable
final class HourlyTimelineModel {
    struct DayMark {
        let start: Double
        let label: String
        /// Compact variant for the minimap ("Heute", "Mo."), where fourteen
        /// full date labels would collide.
        let shortLabel: String
    }

    struct ExtremeMark {
        let timestamp: Double
        let value: Double
        let isHigh: Bool
    }

    // MARK: - Timeline data

    private(set) var times: [Double] = []
    private(set) var temperature: [Double] = []
    private(set) var apparentTemperature: [Double] = []
    private(set) var precipitation: [Double] = []
    private(set) var snowfall: [Double] = []
    private(set) var weathercode: [Double] = []
    private(set) var windspeed: [Double] = []
    private(set) var winddirection: [Double] = []
    private(set) var windspeed80: [Double] = []
    private(set) var windspeed120: [Double] = []
    private(set) var windspeed180: [Double] = []
    private(set) var pressure: [Double] = []
    private(set) var humidity: [Double] = []
    private(set) var cloudcover: [Double] = []
    private(set) var cloudLow: [Double] = []
    private(set) var cloudMid: [Double] = []
    private(set) var cloudHigh: [Double] = []
    private(set) var soilTemperature0: [Double] = []
    private(set) var soilTemperature6: [Double] = []
    private(set) var soilTemperature18: [Double] = []
    private(set) var soilTemperature54: [Double] = []
    private(set) var soilMoisture: [[Double]] = []
    private(set) var et0: [Double] = []
    private(set) var precipitationMax: Double = 2.5
    private(set) var nightRanges: [ClosedRange<Double>] = []
    private(set) var dayMarks: [DayMark] = []
    private(set) var timeZone: TimeZone = .current
    private(set) var precipitationUnit = "mm"
    private(set) var windUnitString = "km/h"
    private(set) var temperatureUnit = "°C"
    private(set) var soilMoistureUnit = "m³/m³"
    private(set) var et0Unit = "mm"

    /// Not observed: mutated lazily from `layout(for:)` during view updates.
    @ObservationIgnored private var layoutCache: [HourlyLens: HourlyLensLayout] = [:]

    var hasData: Bool { times.count > 1 }
    var domain: ClosedRange<Double> { (times.first ?? 0)...(times.last ?? 1) }

    // MARK: - Scrub state

    let windowSeconds: Double = 48 * 3_600
    private(set) var scrubTime: Double = Date.now.timeIntervalSince1970
    /// Coarse (2-min) scrub time for the stage, throttled to ~10 Hz: small
    /// steps at a steady cadence read as continuous sky/sun motion, while the
    /// deck cross-fades stay short enough not to overlap.
    private(set) var stageTime: Double = Date.now.timeIntervalSince1970
    /// Increments when the scrub crosses an hour boundary (haptic trigger).
    private(set) var hourTick = 0

    /// The playhead is pinned to the strip's center: the window is derived
    /// from the scrub, so panning the strip IS scrubbing. Near the data edges
    /// the window simply extends into empty space, keeping the bar centered.
    var windowStart: Double { scrubTime - windowSeconds / 2 }

    var stageDate: Date { Date(timeIntervalSince1970: stageTime) }

    private var panStartTime: Double?
    private var glide: (from: Double, to: Double, start: TimeInterval, duration: TimeInterval, easeOut: Bool)?
    @ObservationIgnored private var stagePushTask: Task<Void, Never>?
    @ObservationIgnored private var lastStagePush: TimeInterval = 0
    /// No deinit cancellation needed: the loop holds self weakly and exits on
    /// its next 16 ms tick once the model is gone.
    private var ticker: Task<Void, Never>?

    // MARK: - Data

    func update(from weather: Weather) {
        let hourly = weather.forecast.hourly
        let newTimes = hourly?.time ?? []
        guard newTimes.count > 1 else {
            times = []
            return
        }

        let firstLoad = !hasData
        times = newTimes
        temperature = hourly?.temperature_2m ?? []
        apparentTemperature = hourly?.apparent_temperature ?? []
        precipitation = hourly?.precipitation ?? []
        snowfall = hourly?.snowfall ?? []
        weathercode = hourly?.weathercode ?? []
        windspeed = hourly?.windspeed_10m ?? []
        winddirection = hourly?.winddirection_10m ?? []
        windspeed80 = hourly?.windspeed_80m ?? []
        windspeed120 = hourly?.windspeed_120m ?? []
        windspeed180 = Self.filled(hourly?.windspeed_180m)
        pressure = hourly?.pressure_msl ?? []
        humidity = hourly?.relativehumidity_2m ?? []
        cloudcover = hourly?.cloudcover ?? []
        cloudLow = hourly?.cloudcover_low ?? []
        cloudMid = hourly?.cloudcover_mid ?? []
        cloudHigh = hourly?.cloudcover_high ?? []
        soilTemperature0 = Self.filled(hourly?.soil_temperature_0cm)
        soilTemperature6 = Self.filled(hourly?.soil_temperature_6cm)
        soilTemperature18 = Self.filled(hourly?.soil_temperature_18cm)
        soilTemperature54 = Self.filled(hourly?.soil_temperature_54cm)
        soilMoisture = [
            Self.filled(hourly?.soil_moisture_27_81cm),
            Self.filled(hourly?.soil_moisture_9_27cm),
            Self.filled(hourly?.soil_moisture_3_9cm),
            Self.filled(hourly?.soil_moisture_1_3cm),
            Self.filled(hourly?.soil_moisture_0_1cm),
        ]
        et0 = hourly?.et0_fao_evapotranspiration ?? []
        precipitationUnit = weather.forecast.hourly_units?.precipitation ?? "mm"
        windUnitString = weather.forecast.hourly_units?.windspeed_10m ?? "km/h"
        temperatureUnit = weather.forecast.hourly_units?.temperature_2m ?? "°C"
        soilMoistureUnit = weather.forecast.hourly_units?.soil_moisture_0_1cm ?? "m³/m³"
        et0Unit = weather.forecast.hourly_units?.et0_fao_evapotranspiration ?? "mm"
        layoutCache = [:]
        timeZone = TimeZone(secondsFromGMT: weather.forecast.utc_offset_seconds ?? 0) ?? .current

        precipitationMax = max(precipitation.max() ?? 0, 2.5)
        nightRanges = Self.nightRanges(times: newTimes, isDay: hourly?.is_day ?? [])
        dayMarks = Self.dayMarks(times: newTimes, timeZone: timeZone)

        if firstLoad {
            let now = Date.now.timeIntervalSince1970
            scrubTime = min(max(now, domain.lowerBound), domain.upperBound)
        } else {
            scrubTime = min(max(scrubTime, domain.lowerBound), domain.upperBound)
        }
        stageTime = quantized(scrubTime)
    }

    /// Optional-element Open-Meteo arrays ([Double?]) forward-filled into plain
    /// values — a nil hour carries the previous reading instead of faking a 0.
    private static func filled(_ values: [Double?]?) -> [Double] {
        var last = 0.0
        return (values ?? []).map { value in
            if let value { last = value }
            return last
        }
    }

    // MARK: - Sampling

    func sample(_ values: [Double]) -> Double? {
        guard hasData else { return nil }
        return AtmosphereWeatherMapper.interpolatedValue(at: scrubTime, times: times, values: values)
    }

    /// Nearest-hour value for categorical series (weather code).
    private func nearestValue(in values: [Double]) -> Double? {
        guard hasData, let first = times.first, !values.isEmpty else { return nil }
        let index = Int(((scrubTime - first) / 3_600).rounded())
        guard values.indices.contains(index) else { return values.last }
        return values[index]
    }

    // MARK: - Readout

    var dateLabel: String {
        guard hasData else { return "" }
        let day = HourlyFormatting.dayLabel(timestamp: scrubTime, timeZone: timeZone, now: .now)
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.day, .month], from: Date(timeIntervalSince1970: scrubTime))
        return day + " \(components.day ?? 0).\(components.month ?? 0)."
    }

    /// The scrubbed day's name: "Heute"/"Morgen", the weekday further out.
    var titleLabel: String {
        guard hasData else { return "" }
        return HourlyFormatting.dayLabel(timestamp: scrubTime, timeZone: timeZone, now: .now)
    }

    /// The small-caps line above the title: weekday and date while the title
    /// is relative ("Samstag · 29. Aug."), the date alone once the title IS
    /// the weekday.
    var eyebrowLabel: String {
        guard hasData else { return "" }
        let date = Date(timeIntervalSince1970: scrubTime)
        let dayMonth = SettingService.formattedDayMonth(date, timeZone: timeZone)
        let weekday = SettingService.formattedWeekday(date, timeZone: timeZone)
        guard titleLabel != weekday else { return dayMonth }
        return weekday + " · " + dayMonth
    }

    var clockLabel: String {
        guard hasData else { return "" }
        // Snap the shown minutes to 10 so the label doesn't flicker mid-drag.
        let displayTime = (scrubTime / 600).rounded(.down) * 600
        return HourlyFormatting.timeString(timestamp: displayTime, timeZone: timeZone)
    }

    var timeLabel: String {
        guard hasData else { return "" }
        return dateLabel + ", " + clockLabel
    }

    var temperatureLabel: String {
        HourlyFormatting.temperatureString(sample(temperature))
    }

    /// The scrubbed day's span ("H:24° T:12°"); nil on partial edge days.
    var dayRangeLabel: String? {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: scrubTime))
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        var high = -Double.infinity
        var low = Double.infinity
        var hours = 0
        for (index, time) in times.enumerated()
        where time >= dayStart.timeIntervalSince1970 && time < dayEnd.timeIntervalSince1970
            && index < temperature.count {
            high = max(high, temperature[index])
            low = min(low, temperature[index])
            hours += 1
        }
        guard hours >= 3 else { return nil }
        return String(
            localized: "H:\(HourlyFormatting.temperatureString(high)) T:\(HourlyFormatting.temperatureString(low))"
        )
    }

    var conditionLabel: String {
        guard hasData else { return "" }
        let code = Int(nearestValue(in: weathercode) ?? 0)
        // Match the stage's sky/rain agreement rule: when the sampled rate says
        // rain while the code stays dry, the label follows the rain.
        let dryCodes = code < 51 || code > 99
        if dryCodes, precipitationRate >= 0.1 {
            return WeatherConditionLabel.text(for: (sample(snowfall) ?? 0) > 0 ? .snow : .rain)
        }
        return WeatherConditionLabel.text(for: code)
    }

    var precipitationRate: Double {
        sample(precipitation) ?? 0
    }

    var windLabel: String {
        guard let speed = sample(windspeed) else { return "--" }
        let unit = WindSpeedUnit(settingValue: SettingService.shared.windSpeedUnit)
        if unit.usesBeaufortDisplay {
            return "\(BeaufortScale.force(forKilometersPerHour: speed)) \(unit.displayUnit)"
        }
        return "\(Int(speed.rounded())) \(windUnitString)"
    }

    /// The deck row's live value at the scrubbed hour, formatted like the
    /// lens' chart labels so row and chart never disagree.
    func rowValue(for lens: HourlyLens) -> String? {
        guard hasData else { return nil }
        let layout = layout(for: lens)
        switch lens {
        case .overview:
            return HourlyFormatting.temperatureString(sample(temperature))
        case .clouds:
            return layout.extremeFormat(sample(cloudcover) ?? 0)
        default:
            guard let primary = layout.primary, let value = sample(primary.values) else { return nil }
            return layout.extremeFormat(value)
        }
    }

    /// Fraction slash keeps "m³⁄m³" compact enough for the value labels.
    private var compactMoistureUnit: String {
        soilMoistureUnit.replacingOccurrences(of: "/", with: "\u{2044}")
    }

    var accessibilityValue: String {
        guard hasData else { return "" }
        return timeLabel + ", " + temperatureLabel + ", " + conditionLabel
            + ", " + String(localized: "Wind") + " " + windLabel
    }

    // MARK: - Lens layouts

    func layout(for lens: HourlyLens) -> HourlyLensLayout {
        if let cached = layoutCache[lens] {
            return cached
        }
        let layout = buildLayout(for: lens)
        layoutCache[lens] = layout
        return layout
    }

    private func buildLayout(for lens: HourlyLens) -> HourlyLensLayout {
        // The format closures capture plain locals, not self: layouts live in
        // a cache on the model, so a self capture would cycle.
        let temperatureUnit = self.temperatureUnit
        let temperatureFormat: (Double) -> String = { "\(Int($0.rounded()))\(temperatureUnit)" }
        let percentFormat: (Double) -> String = { "\(Int($0.rounded()))%" }

        switch lens {
        case .overview:
            return HourlyLensLayout(
                lines: [line(apparentTemperature, .red, width: 3.5,
                             label: String(localized: "Gefühlt")),
                        line(temperature, .orange, label: String(localized: "Temperatur"))],
                domain: paddedDomain([temperature, apparentTemperature]),
                showsBars: true,
                barsAlpha: 0.75,
                fillsPrimary: false,
                extremes: extremeMarks(for: temperature),
                extremeFormat: temperatureFormat,
                primaryColor: .orange,
                barsLabel: String(localized: "Regen")
            )
        case .wind:
            let unit = WindSpeedUnit(settingValue: SettingService.shared.windSpeedUnit)
            let displayed: ([Double]) -> [Double] = unit.usesBeaufortDisplay
                ? BeaufortScale.convertedValues(fromKilometersPerHour:)
                : { $0 }
            // Highest altitude first: the readout box lists lines in reverse,
            // so its rows read 10 m upwards.
            let heights = [windspeed180, windspeed120, windspeed80].map(displayed)
            let heightColors: [Color] = [.teal.mix(with: .black, by: 0.55),
                                         .teal.mix(with: .black, by: 0.4),
                                         .teal.mix(with: .black, by: 0.25)]
            let heightLabels = ["180 m", "120 m", "80 m"]
            let speeds = displayed(windspeed)
            let windUnit = unit.usesBeaufortDisplay ? unit.displayUnit : windUnitString
            return HourlyLensLayout(
                lines: zip(zip(heights, heightColors), heightLabels).map { pair, label in
                    line(pair.0, pair.1, width: 2.5, label: label)
                } + [line(speeds, .teal, label: "10 m")],
                domain: paddedDomain(heights + [speeds], from: 0),
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                extremes: [],
                extremeFormat: { "\(Int($0.rounded())) \(windUnit)" },
                primaryColor: .teal,
                showsDirectionArrows: true
            )
        case .pressure:
            return HourlyLensLayout(
                lines: [line(pressure, .purple)],
                domain: paddedDomain([pressure], minimumPad: 2),
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                extremes: extremeMarks(for: pressure),
                extremeFormat: { "\(Int($0.rounded())) hPa" },
                primaryColor: .purple
            )
        case .humidity:
            return HourlyLensLayout(
                lines: [line(humidity, .mint)],
                domain: 0...105,
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                extremes: extremeMarks(for: humidity),
                extremeFormat: percentFormat,
                primaryColor: .mint
            )
        case .clouds:
            return HourlyLensLayout(
                lines: [],
                domain: 0...1,
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                extremes: [],
                extremeFormat: percentFormat,
                primaryColor: .hourlyCloud,
                bands: [.init(values: cloudHigh, centerFraction: 0.30, label: String(localized: "Hohe Wolken")),
                        .init(values: cloudMid, centerFraction: 0.53, label: String(localized: "Mittlere Wolken")),
                        .init(values: cloudLow, centerFraction: 0.76, label: String(localized: "Tiefe Wolken"))]
            )
        case .soilTemperature:
            return HourlyLensLayout(
                lines: [line(soilTemperature54, .brown.mix(with: .black, by: 0.55), width: 2.5, label: "54 cm"),
                        line(soilTemperature18, .brown.mix(with: .black, by: 0.4), width: 2.8, label: "18 cm"),
                        line(soilTemperature6, .brown.mix(with: .black, by: 0.25), width: 3.1, label: "6 cm"),
                        line(soilTemperature0, .brown, label: "0 cm")],
                domain: paddedDomain([soilTemperature0, soilTemperature6, soilTemperature18, soilTemperature54]),
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                extremes: [],
                extremeFormat: temperatureFormat,
                primaryColor: .brown
            )
        case .soilMoisture:
            let depths = soilMoisture
            let depthColors: [Color] = [.blue.mix(with: .black, by: 0.6),
                                        .blue.mix(with: .black, by: 0.48),
                                        .blue.mix(with: .black, by: 0.35),
                                        .blue.mix(with: .black, by: 0.2)]
            let depthLabels = ["27–81 cm", "9–27 cm", "3–9 cm", "1–3 cm"]
            let secondaries = zip(zip(depths.dropLast(), depthColors), depthLabels).map { pair, label in
                line(pair.0, pair.1, width: 2.5, label: label)
            }
            return HourlyLensLayout(
                lines: secondaries + [line(depths.last ?? [], .blue, label: "0–1 cm")],
                domain: paddedDomain(depths, minimumPad: 0.02),
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                extremes: [],
                extremeFormat: { [moistureUnit = compactMoistureUnit] in
                    "\($0.formatted(.number.precision(.fractionLength(2)))) \(moistureUnit)"
                },
                primaryColor: .blue
            )
        case .evapotranspiration:
            return HourlyLensLayout(
                lines: [line(et0, .hourlyRain)],
                domain: paddedDomain([et0], from: 0, minimumPad: 0.05),
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                extremes: extremeMarks(for: et0, highsOnly: true, atLeast: 0.05),
                extremeFormat: { [unit = et0Unit] in
                    "\($0.formatted(.number.precision(.fractionLength(2)))) \(unit)"
                },
                primaryColor: .hourlyRain
            )
        }
    }

    private func line(
        _ values: [Double],
        _ color: Color,
        width: CGFloat = 4,
        dashed: Bool = false,
        opacity: Double = 1,
        label: String? = nil
    ) -> HourlyLensLayout.Line {
        HourlyLensLayout.Line(
            values: values, color: color, width: width, dashed: dashed, opacity: opacity, label: label
        )
    }

    /// Joint min/max over all series, padded so curves don't kiss the edges.
    /// `from` pins the lower bound (wind and ET₀ start at zero).
    private func paddedDomain(
        _ series: [[Double]],
        from lowerPin: Double? = nil,
        minimumPad: Double = 0.5
    ) -> ClosedRange<Double> {
        let all = series.flatMap { $0 }
        guard var low = all.min(), var high = all.max() else { return 0...1 }
        let pad = max((high - low) * 0.08, minimumPad)
        low = lowerPin ?? (low - pad)
        high += pad
        guard high > low else { return low...(low + 1) }
        return low...high
    }

    private func extremeMarks(
        for values: [Double],
        highsOnly: Bool = false,
        atLeast threshold: Double = -.infinity
    ) -> [ExtremeMark] {
        let marks = Self.dailyExtremes(times: times, values: values, timeZone: timeZone)
        guard highsOnly else { return marks }
        return marks.filter { $0.isHigh && $0.value >= threshold }
    }

    // MARK: - Scrubbing

    func beginPan() {
        glide = nil
        panStartTime = scrubTime
    }

    /// Panning the strip scrubs: content follows the finger while the playhead
    /// stays pinned to the center, so dragging left pulls the future in.
    func pan(byFraction deltaFraction: Double) {
        guard let panStartTime else { return }
        setScrub(panStartTime - deltaFraction * windowSeconds)
    }

    /// Lets a fast pan coast on, using the gesture's predicted overshoot.
    func endPan(coastFraction: Double = 0) {
        panStartTime = nil
        guard abs(coastFraction) > 0.02 else { return }
        glide(to: scrubTime - coastFraction * windowSeconds, easeOut: true)
    }

    /// A tap on the strip glides the tapped time under the centered playhead.
    func tap(atFraction fraction: Double) {
        glide(to: windowStart + fraction * windowSeconds)
    }

    /// Absolute scrub used by the sky drag and the minimap.
    func scrub(to time: Double) {
        glide = nil
        setScrub(time)
    }

    /// VoiceOver + keyboard stepping.
    func nudge(hours: Double) {
        scrub(to: scrubTime + hours * 3_600)
    }

    /// Eased jump for taps and pan coasting; instant under Reduce Motion.
    /// `easeOut` skips the slow-in so a fling keeps its speed.
    func glide(to time: Double, easeOut: Bool = false) {
        panStartTime = nil
        guard hasData else { return }
        let target = min(max(time, domain.lowerBound), domain.upperBound)
        guard !UIAccessibility.isReduceMotionEnabled else {
            setScrub(target)
            return
        }
        let distanceHours = abs(target - scrubTime) / 3_600
        let duration = easeOut
            ? min(1.2, 0.35 + distanceHours * 0.015)
            : min(2.2, 0.6 + distanceHours * 0.02)
        glide = (scrubTime, target, CACurrentMediaTime(), duration, easeOut)
        startTickerIfNeeded()
    }

    private func setScrub(_ time: Double) {
        guard hasData else { return }
        let clamped = min(max(time, domain.lowerBound), domain.upperBound)
        let previousHour = Int(scrubTime / 3_600)
        scrubTime = clamped
        if Int(clamped / 3_600) != previousHour {
            hourTick &+= 1
        }
        pushStage(quantized(clamped))
    }

    private func pushStage(_ quantizedTime: Double) {
        guard quantizedTime != stageTime else { return }
        let now = CACurrentMediaTime()
        if now - lastStagePush > 0.1 {
            stagePushTask?.cancel()
            stagePushTask = nil
            lastStagePush = now
            stageTime = quantizedTime
        } else if stagePushTask == nil {
            stagePushTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, !Task.isCancelled else { return }
                self.stagePushTask = nil
                self.lastStagePush = CACurrentMediaTime()
                self.stageTime = self.quantized(self.scrubTime)
            }
        }
    }

    private func quantized(_ time: Double) -> Double {
        (time / 120).rounded() * 120
    }

    // MARK: - Ticker

    private func startTickerIfNeeded() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self else { return }
                if !self.tick() {
                    self.ticker = nil
                    return
                }
            }
        }
    }

    /// One ticker frame; returns false once there is nothing left to animate.
    private func tick() -> Bool {
        if let glide {
            let progress = min(1, (CACurrentMediaTime() - glide.start) / max(glide.duration, 0.01))
            let eased: Double
            if glide.easeOut {
                eased = 1 - pow(1 - progress, 3)
            } else {
                eased = progress < 0.5
                    ? 4 * pow(progress, 3)
                    : 1 - pow(-2 * progress + 2, 3) / 2
            }
            setScrub(glide.from + (glide.to - glide.from) * eased)
            if progress >= 1 {
                self.glide = nil
            }
        }

        return glide != nil
    }

    // MARK: - Derived timeline features

    private static func nightRanges(times: [Double], isDay: [Double]) -> [ClosedRange<Double>] {
        guard times.count == isDay.count, !times.isEmpty else { return [] }
        var ranges: [ClosedRange<Double>] = []
        var start: Double?
        for (index, flag) in isDay.enumerated() {
            let isNight = flag < 0.5
            if isNight, start == nil {
                start = times[index]
            }
            if !isNight, let opened = start {
                if times[index] > opened {
                    ranges.append(opened...times[index])
                }
                start = nil
            }
        }
        if let opened = start, let last = times.last, last > opened {
            ranges.append(opened...last)
        }
        return ranges
    }

    private static func dayMarks(times: [Double], timeZone: TimeZone) -> [DayMark] {
        guard let first = times.first, let last = times.last else { return [] }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let now = Date.now

        var marks: [DayMark] = []
        var dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: first))
        while dayStart.timeIntervalSince1970 <= last {
            let start = max(dayStart.timeIntervalSince1970, first)
            let weekday = HourlyFormatting.weekdayString(
                timestamp: dayStart.timeIntervalSince1970,
                timeZone: timeZone
            )
            let label: String
            let shortLabel: String
            if calendar.isDate(dayStart, inSameDayAs: now) {
                label = String(localized: "Heute")
                shortLabel = label
            } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                      calendar.isDate(dayStart, inSameDayAs: tomorrow) {
                label = String(localized: "Morgen")
                shortLabel = weekday
            } else {
                label = weekday
                shortLabel = weekday
            }
            let dayNumber = calendar.component(.day, from: dayStart)
            let monthNumber = calendar.component(.month, from: dayStart)
            marks.append(DayMark(
                start: start,
                label: label + " \(dayNumber).\(monthNumber).",
                shortLabel: shortLabel
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            dayStart = next
        }
        return marks
    }

    private static func dailyExtremes(times: [Double], values: [Double], timeZone: TimeZone) -> [ExtremeMark] {
        guard times.count == values.count, !times.isEmpty else { return [] }
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        var marks: [ExtremeMark] = []
        var index = 0
        while index < times.count {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: times[index]))
            var highIndex = index
            var lowIndex = index
            var next = index
            while next < times.count,
                  calendar.isDate(Date(timeIntervalSince1970: times[next]), inSameDayAs: day) {
                if values[next] > values[highIndex] { highIndex = next }
                if values[next] < values[lowIndex] { lowIndex = next }
                next += 1
            }
            // Partial edge days with only a couple of hours would stack both
            // marks on nearly the same point — skip those.
            if next - index >= 3 {
                marks.append(ExtremeMark(timestamp: times[highIndex], value: values[highIndex], isHigh: true))
                if lowIndex != highIndex {
                    marks.append(ExtremeMark(timestamp: times[lowIndex], value: values[lowIndex], isHigh: false))
                }
            }
            index = next
        }
        return marks
    }
}
