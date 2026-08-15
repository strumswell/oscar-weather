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
    }

    struct ExtremeMark {
        let timestamp: Double
        let value: Double
        let isHigh: Bool
    }

    enum HUDSwatch {
        case line(dashed: Bool)
        case bar
        case none
    }

    struct HUDStat: Identifiable {
        let label: String
        let value: String
        var color: Color?
        var swatch: HUDSwatch = .none
        var arrowDegrees: Double?

        var id: String { label }
    }

    struct CardHeader {
        let title: LocalizedStringKey
        let value: String
        let badge: String?
        let color: Color
        let subtitle: LocalizedStringKey
    }

    // MARK: - Timeline data

    private(set) var times: [Double] = []
    private(set) var temperature: [Double] = []
    private(set) var apparentTemperature: [Double] = []
    private(set) var precipitation: [Double] = []
    private(set) var snowfall: [Double] = []
    private(set) var probability: [Double] = []
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
    private(set) var timeZone: TimeZone = .current
    private(set) var precipitationUnit = "mm"
    private(set) var windUnitString = "km/h"
    private(set) var temperatureUnit = "°C"
    private(set) var soilMoistureUnit = "m³/m³"
    private(set) var et0Unit = "mm"

    /// The active strip lens; switching keeps playhead and window untouched.
    var lens: HourlyLens = .overview

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
        probability = (hourly?.precipitation_probability ?? []).map { $0 ?? 0 }
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

    var feelsLabel: String {
        HourlyFormatting.temperatureString(sample(apparentTemperature))
    }

    var rainLabel: String {
        let rate = precipitationRate
        if rate >= 0.05 {
            return HourlyFormatting.precipitationString(value: rate, unit: precipitationUnit)
        }
        let chance = sample(probability) ?? 0
        return "\(Int(chance.rounded())) %"
    }

    var windLabel: String {
        guard let speed = sample(windspeed) else { return "--" }
        let unit = WindSpeedUnit(settingValue: SettingService.shared.windSpeedUnit)
        if unit.usesBeaufortDisplay {
            return "\(BeaufortScale.force(forKilometersPerHour: speed)) \(unit.displayUnit)"
        }
        return "\(Int(speed.rounded())) \(windUnitString)"
    }

    /// Old chart-card header: title, the scrubbed hour's key values, and a
    /// subtitle saying what the chart shows (copy from the retired cards).
    var cardHeader: CardHeader {
        switch lens {
        case .overview:
            return CardHeader(title: "Überblick", value: temperatureLabel,
                              badge: rainLabel, color: .hourlyRain,
                              subtitle: "Temperatur und Niederschlag")
        case .temperature:
            return CardHeader(title: "Temperatur", value: temperatureLabel,
                              badge: String(localized: "Gefühlt") + " " + feelsLabel, color: .orange,
                              subtitle: "Lufttemperatur und gefühlte Temperatur")
        case .precipitation:
            return CardHeader(title: "Niederschlag", value: rainLabel,
                              badge: percentString(sample(probability)), color: .hourlyRain,
                              subtitle: "Regen und Schnee pro Stunde")
        case .wind:
            return CardHeader(title: "Wind", value: windLabel,
                              badge: String(localized: "Böen") + " " + gustLabel, color: .teal,
                              subtitle: "Windgeschwindigkeit in mehreren Höhen")
        case .pressure:
            let trend = pressureTrendLabel
            return CardHeader(title: "Luftdruck", value: pressureLabel,
                              badge: trend == "--" ? nil : trend,
                              color: .purple.mix(with: .black, by: 0.15),
                              subtitle: "Meeresspiegel-Luftdruck")
        case .humidity:
            return CardHeader(title: "Luftfeuchtigkeit", value: percentString(sample(humidity)),
                              badge: String(localized: "Gefühlt") + " " + feelsLabel,
                              color: .mint.mix(with: .black, by: 0.2),
                              subtitle: "Relative Luftfeuchtigkeit")
        case .clouds:
            return CardHeader(title: "Wolken", value: percentString(sample(cloudcover)),
                              badge: nil, color: .gray,
                              subtitle: "Bedeckung in drei Höhenschichten")
        case .soilTemperature:
            return CardHeader(title: "Bodentemperatur",
                              value: HourlyFormatting.temperatureString(sample(soilTemperature0)),
                              badge: nil,
                              color: .brown,
                              subtitle: "Temperatur in mehreren Bodentiefen")
        case .soilMoisture:
            return CardHeader(title: "Bodenwassergehalt",
                              value: moistureString(soilMoisture.last),
                              badge: nil, color: .blue,
                              subtitle: "Volumetrischer Wassergehalt je Bodentiefe")
        case .evapotranspiration:
            let value = sample(et0).map {
                $0.formatted(.number.precision(.fractionLength(2))) + " " + et0Unit
            } ?? "--"
            return CardHeader(title: "Referenz-Evapotranspiration", value: value,
                              badge: nil, color: .hourlyRain,
                              subtitle: "Wasserverlust einer Referenzfläche")
        }
    }

    /// The sim readout row: lensStats minus what the header already shows big
    /// (the temperature itself, wind's Böen badge, pressure's Wind filler) and
    /// context stats the user pruned. The card legend keeps the full list.
    var hudStats: [HUDStat] {
        let excluded: Set<String>
        switch lens {
        case .overview:
            excluded = [String(localized: "Temperatur")]
        case .temperature:
            excluded = [String(localized: "Temperatur"),
                        String(localized: "Feuchte"),
                        String(localized: "Wind")]
        case .pressure:
            excluded = [String(localized: "Wind")]
        default:
            excluded = []
        }
        return lensStats.filter { !excluded.contains($0.label) }
    }

    /// Every series of the active lens, dot-colored to match its line.
    var lensStats: [HUDStat] {
        let feels = HUDStat(label: String(localized: "Gefühlt"), value: feelsLabel)
        let rain = HUDStat(label: String(localized: "Regen"), value: rainLabel)
        let wind = HUDStat(label: String(localized: "Wind"), value: windLabel)
        let humidityStat = HUDStat(label: String(localized: "Feuchte"), value: percentString(sample(humidity)))

        switch lens {
        case .overview:
            return [HUDStat(label: String(localized: "Temperatur"), value: temperatureLabel,
                            color: .orange, swatch: .line(dashed: false)),
                    HUDStat(label: String(localized: "Regen"), value: rainLabel,
                            color: .hourlyRain, swatch: .bar),
                    feels, wind]
        case .temperature:
            return [HUDStat(label: String(localized: "Temperatur"), value: temperatureLabel,
                            color: .orange, swatch: .line(dashed: false)),
                    HUDStat(label: String(localized: "Gefühlt"), value: feelsLabel,
                            color: .orange.mix(with: .black, by: 0.25), swatch: .line(dashed: true)),
                    humidityStat, wind]
        case .precipitation:
            var stats = [HUDStat(label: String(localized: "Regen"), value: rainLabel,
                                 color: .hourlyRain, swatch: .bar),
                         HUDStat(label: String(localized: "Chance"),
                                 value: percentString(sample(probability)),
                                 color: .blue.mix(with: .black, by: 0.3), swatch: .line(dashed: true))]
            if let snow = sample(snowfall), snow > 0.005 {
                stats.append(HUDStat(
                    label: String(localized: "Schnee"),
                    value: snow.formatted(.number.precision(.fractionLength(1))) + " cm",
                    color: .cyan, swatch: .bar
                ))
            }
            stats.append(HUDStat(label: String(localized: "Wolken"), value: percentString(sample(cloudcover))))
            return stats
        case .wind:
            let direction = nearestValue(in: winddirection)
            return [HUDStat(label: "10 m", value: windLabel,
                            color: .teal, swatch: .line(dashed: false)),
                    HUDStat(label: "80 m", value: speedLabel(sample(windspeed80)),
                            color: .teal.mix(with: .black, by: 0.25), swatch: .line(dashed: false)),
                    HUDStat(label: "120 m", value: speedLabel(sample(windspeed120)),
                            color: .teal.mix(with: .black, by: 0.4), swatch: .line(dashed: false)),
                    HUDStat(label: "180 m", value: speedLabel(sample(windspeed180)),
                            color: .teal.mix(with: .black, by: 0.55), swatch: .line(dashed: false)),
                    HUDStat(
                        label: String(localized: "Richtung"),
                        value: direction.map { "\(Int($0.rounded()))°" } ?? "--",
                        arrowDegrees: direction.map { ($0 + 180).truncatingRemainder(dividingBy: 360) }
                    )]
        case .pressure:
            return [HUDStat(label: String(localized: "Druck"), value: pressureLabel,
                            color: .purple.mix(with: .black, by: 0.15), swatch: .line(dashed: false)),
                    HUDStat(label: String(localized: "Tendenz"), value: pressureTrendLabel),
                    wind]
        case .humidity:
            return [HUDStat(label: String(localized: "Feuchte"),
                            value: percentString(sample(humidity)),
                            color: .mint.mix(with: .black, by: 0.2), swatch: .line(dashed: false)),
                    feels, rain]
        case .clouds:
            return [HUDStat(label: String(localized: "Wolken"), value: percentString(sample(cloudcover))),
                    HUDStat(label: String(localized: "Hohe Wolken"),
                            value: percentString(sample(cloudHigh)), color: .hourlyCloud, swatch: .bar),
                    HUDStat(label: String(localized: "Mittlere Wolken"),
                            value: percentString(sample(cloudMid)), color: .hourlyCloud, swatch: .bar),
                    HUDStat(label: String(localized: "Tiefe Wolken"),
                            value: percentString(sample(cloudLow)), color: .hourlyCloud, swatch: .bar)]
        case .soilTemperature:
            return [HUDStat(label: "0 cm",
                            value: HourlyFormatting.temperatureString(sample(soilTemperature0)),
                            color: .brown, swatch: .line(dashed: false)),
                    HUDStat(label: "6 cm",
                            value: HourlyFormatting.temperatureString(sample(soilTemperature6)),
                            color: .brown.mix(with: .black, by: 0.25), swatch: .line(dashed: false)),
                    HUDStat(label: "18 cm",
                            value: HourlyFormatting.temperatureString(sample(soilTemperature18)),
                            color: .brown.mix(with: .black, by: 0.4), swatch: .line(dashed: false)),
                    HUDStat(label: "54 cm",
                            value: HourlyFormatting.temperatureString(sample(soilTemperature54)),
                            color: .brown.mix(with: .black, by: 0.55), swatch: .line(dashed: false))]
        case .soilMoisture:
            let depths = soilMoisture
            return [HUDStat(label: "0–1 cm", value: moistureString(depths.last),
                            color: .blue, swatch: .line(dashed: false)),
                    HUDStat(label: "1–3 cm", value: moistureString(depths.count > 3 ? depths[3] : nil),
                            color: .blue.mix(with: .black, by: 0.2), swatch: .line(dashed: false)),
                    HUDStat(label: "3–9 cm", value: moistureString(depths.count > 2 ? depths[2] : nil),
                            color: .blue.mix(with: .black, by: 0.35), swatch: .line(dashed: false)),
                    HUDStat(label: "9–27 cm", value: moistureString(depths.count > 1 ? depths[1] : nil),
                            color: .blue.mix(with: .black, by: 0.48), swatch: .line(dashed: false)),
                    HUDStat(label: "27–81 cm", value: moistureString(depths.first),
                            color: .blue.mix(with: .black, by: 0.6), swatch: .line(dashed: false))]
        case .evapotranspiration:
            let value = sample(et0).map {
                $0.formatted(.number.precision(.fractionLength(2))) + " " + et0Unit
            } ?? "--"
            return [HUDStat(label: "ET₀", value: value, color: .hourlyRain, swatch: .line(dashed: false)),
                    humidityStat, wind]
        }
    }

    private func speedLabel(_ speed: Double?) -> String {
        guard let speed else { return "--" }
        let unit = WindSpeedUnit(settingValue: SettingService.shared.windSpeedUnit)
        if unit.usesBeaufortDisplay {
            return "\(BeaufortScale.force(forKilometersPerHour: speed)) \(unit.displayUnit)"
        }
        return "\(Int(speed.rounded())) \(windUnitString)"
    }

    private var gustLabel: String {
        speedLabel(sample(windgusts))
    }

    private var pressureLabel: String {
        guard let value = sample(pressure) else { return "--" }
        return "\(Int(value.rounded())) hPa"
    }

    /// Signed pressure change over the 3 hours leading up to the scrub.
    private var pressureTrendLabel: String {
        let earlier = scrubTime - 3 * 3_600
        guard earlier >= domain.lowerBound,
              let now = sample(pressure),
              let past = AtmosphereWeatherMapper.interpolatedValue(at: earlier, times: times, values: pressure)
        else { return "--" }
        let delta = now - past
        return delta.formatted(
            .number.sign(strategy: .always(includingZero: false)).precision(.fractionLength(1))
        ) + " hPa"
    }

    private func percentString(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded())) %"
    }

    /// Fraction slash keeps "m³⁄m³" compact enough for the readout cells.
    private var compactMoistureUnit: String {
        soilMoistureUnit.replacingOccurrences(of: "/", with: "\u{2044}")
    }

    private func moistureString(_ values: [Double]?) -> String {
        guard let values, let value = sample(values) else { return "--" }
        return value.formatted(.number.precision(.fractionLength(2))) + " " + compactMoistureUnit
    }

    var accessibilityValue: String {
        guard hasData else { return "" }
        return timeLabel + ", " + temperatureLabel + ", " + conditionLabel
            + ", " + String(localized: "Wind") + " " + windLabel
    }

    var isAwayFromNow: Bool {
        abs(scrubTime - Date.now.timeIntervalSince1970) > 1_800
    }

    /// Signed offset to now, scale-aware ("+35 Min.", "+5 Std.", "+3 Tg.").
    var nowDeltaLabel: String {
        let delta = scrubTime - Date.now.timeIntervalSince1970
        let formatted = Self.deltaFormatter.string(from: abs(delta)) ?? ""
        return (delta > 0 ? "+" : "−") + formatted
    }

    private static let deltaFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        return formatter
    }()

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
        let f0: (Double) -> String = { "\(Int($0.rounded()))" }
        let f1: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(1))) }
        let f2: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(2))) }

        switch lens {
        case .overview:
            return HourlyLensLayout(
                lines: [line(temperature, .orange)],
                domain: paddedDomain([temperature]),
                showsBars: true,
                barsAlpha: 0.75,
                fillsPrimary: false,
                topLabel: temperatureUnit.uppercased(),
                bottomLabel: precipitationUnit.uppercased(),
                extremes: extremeMarks(for: temperature),
                extremeFormat: HourlyFormatting.temperatureString,
                ridesBars: false,
                primaryColor: .orange
            )
        case .temperature:
            return HourlyLensLayout(
                lines: [line(apparentTemperature, .orange.mix(with: .black, by: 0.25), width: 1.5, dashed: true),
                        line(temperature, .orange)],
                domain: paddedDomain([temperature, apparentTemperature]),
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                topLabel: temperatureUnit.uppercased(),
                bottomLabel: nil,
                extremes: extremeMarks(for: temperature),
                extremeFormat: HourlyFormatting.temperatureString,
                ridesBars: false,
                primaryColor: .orange
            )
        case .precipitation:
            return HourlyLensLayout(
                lines: [line(probability, .blue.mix(with: .black, by: 0.3), width: 1.5, dashed: true)],
                domain: 0...108,
                showsBars: true,
                barsAlpha: 0.95,
                fillsPrimary: false,
                topLabel: "%",
                bottomLabel: precipitationUnit.uppercased(),
                extremes: extremeMarks(for: precipitation, highsOnly: true, atLeast: 0.4),
                extremeFormat: f1,
                ridesBars: true,
                primaryColor: .hourlyRain
            )
        case .wind:
            let unit = WindSpeedUnit(settingValue: SettingService.shared.windSpeedUnit)
            let displayed: ([Double]) -> [Double] = unit.usesBeaufortDisplay
                ? BeaufortScale.convertedValues(fromKilometersPerHour:)
                : { $0 }
            let heights = [windspeed80, windspeed120, windspeed180].map(displayed)
            let heightColors: [Color] = [.teal.mix(with: .black, by: 0.25),
                                         .teal.mix(with: .black, by: 0.4),
                                         .teal.mix(with: .black, by: 0.55)]
            let speeds = displayed(windspeed)
            return HourlyLensLayout(
                lines: zip(heights, heightColors).map { line($0, $1, width: 1.2) }
                    + [line(speeds, .teal)],
                domain: paddedDomain(heights + [speeds], from: 0),
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                topLabel: unit.usesBeaufortDisplay ? "BFT" : windUnitString.uppercased(),
                bottomLabel: nil,
                extremes: extremeMarks(for: speeds),
                extremeFormat: f0,
                ridesBars: false,
                primaryColor: .teal,
                showsDirectionArrows: true
            )
        case .pressure:
            return HourlyLensLayout(
                lines: [line(pressure, .purple.mix(with: .black, by: 0.15))],
                domain: paddedDomain([pressure], minimumPad: 2),
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                topLabel: "HPA",
                bottomLabel: nil,
                extremes: extremeMarks(for: pressure),
                extremeFormat: f0,
                ridesBars: false,
                primaryColor: .purple.mix(with: .black, by: 0.15)
            )
        case .humidity:
            return HourlyLensLayout(
                lines: [line(humidity, .mint.mix(with: .black, by: 0.2))],
                domain: 0...105,
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                topLabel: "%",
                bottomLabel: nil,
                extremes: extremeMarks(for: humidity),
                extremeFormat: f0,
                ridesBars: false,
                primaryColor: .mint.mix(with: .black, by: 0.2)
            )
        case .clouds:
            return HourlyLensLayout(
                lines: [],
                domain: 0...1,
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                topLabel: nil,
                bottomLabel: nil,
                extremes: [],
                extremeFormat: f0,
                ridesBars: false,
                primaryColor: .gray,
                bands: [.init(values: cloudHigh, centerFraction: 0.30, label: String(localized: "Hohe Wolken")),
                        .init(values: cloudMid, centerFraction: 0.53, label: String(localized: "Mittlere Wolken")),
                        .init(values: cloudLow, centerFraction: 0.76, label: String(localized: "Tiefe Wolken"))]
            )
        case .soilTemperature:
            return HourlyLensLayout(
                lines: [line(soilTemperature54, .brown.mix(with: .black, by: 0.55), width: 1.2),
                        line(soilTemperature18, .brown.mix(with: .black, by: 0.4), width: 1.4),
                        line(soilTemperature6, .brown.mix(with: .black, by: 0.25), width: 1.6),
                        line(soilTemperature0, .brown)],
                domain: paddedDomain([soilTemperature0, soilTemperature6, soilTemperature18, soilTemperature54]),
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                topLabel: temperatureUnit.uppercased(),
                bottomLabel: nil,
                extremes: extremeMarks(for: soilTemperature0),
                extremeFormat: HourlyFormatting.temperatureString,
                ridesBars: false,
                primaryColor: .brown
            )
        case .soilMoisture:
            let depths = soilMoisture
            let depthColors: [Color] = [.blue.mix(with: .black, by: 0.6),
                                        .blue.mix(with: .black, by: 0.48),
                                        .blue.mix(with: .black, by: 0.35),
                                        .blue.mix(with: .black, by: 0.2)]
            let secondaries = zip(depths.dropLast(), depthColors).map { values, color in
                line(values, color, width: 1.2)
            }
            return HourlyLensLayout(
                lines: secondaries + [line(depths.last ?? [], .blue)],
                domain: paddedDomain(depths, minimumPad: 0.02),
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                topLabel: compactMoistureUnit.uppercased(),
                bottomLabel: nil,
                extremes: extremeMarks(for: depths.last ?? []),
                extremeFormat: f2,
                ridesBars: false,
                primaryColor: .blue
            )
        case .evapotranspiration:
            return HourlyLensLayout(
                lines: [line(et0, .hourlyRain)],
                domain: paddedDomain([et0], from: 0, minimumPad: 0.05),
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: true,
                topLabel: et0Unit.uppercased(),
                bottomLabel: nil,
                extremes: extremeMarks(for: et0, highsOnly: true, atLeast: 0.05),
                extremeFormat: f2,
                ridesBars: false,
                primaryColor: .hourlyRain
            )
        }
    }

    private func line(
        _ values: [Double],
        _ color: Color,
        width: CGFloat = 2,
        dashed: Bool = false,
        opacity: Double = 1
    ) -> HourlyLensLayout.Line {
        HourlyLensLayout.Line(values: values, color: color, width: width, dashed: dashed, opacity: opacity)
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
            let label: String
            if calendar.isDate(dayStart, inSameDayAs: now) {
                label = String(localized: "Heute")
            } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                      calendar.isDate(dayStart, inSameDayAs: tomorrow) {
                label = String(localized: "Morgen")
            } else {
                label = HourlyFormatting.weekdayString(
                    timestamp: dayStart.timeIntervalSince1970,
                    timeZone: timeZone
                )
            }
            let dayNumber = calendar.component(.day, from: dayStart)
            let monthNumber = calendar.component(.month, from: dayStart)
            marks.append(DayMark(start: start, label: label + " \(dayNumber).\(monthNumber)."))
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
