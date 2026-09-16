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
    private(set) var windgusts: [Double] = []
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
    private(set) var chapters: [ChapterEngine.Chapter] = []
    private(set) var radarTimes: [Double] = []
    private(set) var radarRates: [Double] = []
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
    var isGliding: Bool { glide != nil }

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
        windgusts = hourly?.windgusts_10m ?? []
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
        timeZone = weather.forecast.locationTimeZone

        precipitationMax = max(precipitation.max() ?? 0, 2.5)
        nightRanges = Self.nightRanges(times: newTimes, isDay: hourly?.is_day ?? [])
        dayMarks = Self.dayMarks(times: newTimes, timeZone: timeZone)
        let radarPoints = (weather.precipSeries?.series ?? []).sorted { $0.timestamp < $1.timestamp }
        radarTimes = radarPoints.map { $0.timestamp.timeIntervalSince1970 }
        radarRates = radarPoints.map(\.precipitation)
        chapters = ChapterEngine.chapters(
            from: ChapterEngine.Input(
                times: newTimes,
                temperature: temperature,
                precipitation: precipitation,
                snowfall: snowfall,
                weathercode: weathercode,
                windgusts: windgusts,
                cloudcover: cloudcover,
                pressure: pressure,
                isDay: hourly?.is_day ?? [],
                timeZone: timeZone,
                now: Date.now.timeIntervalSince1970,
                precipitationUnit: precipitationUnit,
                windUnitString: windUnitString,
                windSpeedUnit: WindSpeedUnit(settingValue: SettingService.shared.windSpeedUnit),
                sunrises: weather.forecast.daily?.sunrise ?? [],
                sunsets: weather.forecast.daily?.sunset ?? [],
                radarTimes: radarTimes,
                radarRates: radarRates,
                alertEvents: weather.alerts.displayInfos.map { info in
                    ChapterEngine.AlertEvent(
                        id: info.id,
                        title: info.event,
                        detail: info.details ?? info.headline,
                        onset: info.onset?.timeIntervalSince1970,
                        expires: info.expires?.timeIntervalSince1970,
                        severityRank: info.severityRank,
                        source: info.source
                    )
                }
            ),
            includingPast: true,
            limit: nil
        )

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

    /// Half-open: hours with `start <= time < end`.
    func hourIndices(from start: Double, until end: Double) -> [Int]? {
        guard hasData else { return nil }
        let indices = times.indices.filter { times[$0] >= start && times[$0] < end }
        return indices.isEmpty ? nil : indices
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

}
