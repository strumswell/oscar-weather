import CoreLocation
import SwiftUI

/// The ensemble page's data and selected day. Chart, rail, rows and caption
/// observe one instance, so picking a day anywhere moves all of them.
@MainActor
@Observable
final class EnsembleState {
    var model: DailyEnsembleModel = .ecmwfIFS025Ensemble
    var selectedIndex = 0
    private(set) var days: [EnsembleDay] = []
    private(set) var isLoading = true
    private(set) var timeZone: TimeZone = .current
    private(set) var utcOffsetSeconds = 0
    private(set) var isFahrenheit = false
    private(set) var precipitationUnit = "mm"
    private(set) var windUnit = "km/h"
    private(set) var usesBeaufort = false

    @ObservationIgnored private var loadGeneration = 0

    var selectedDay: EnsembleDay? {
        days.indices.contains(selectedIndex) ? days[selectedIndex] : nil
    }

    /// Keeps the selected date across model switches; the first load lands on `anchor`.
    func load(at coordinates: CLLocationCoordinate2D, anchor: Date) async {
        loadGeneration += 1
        let generation = loadGeneration
        let anchorTime = selectedDay?.noon ?? anchor.timeIntervalSince1970
        isLoading = true
        do {
            let response = try await APIClient.shared.getDailyEnsembleForecast(coordinates: coordinates, model: model)
            guard generation == loadGeneration else { return }
            apply(response, anchorTime: anchorTime)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard generation == loadGeneration else { return }
            days = []
        }
        isLoading = false
    }

    private func apply(_ response: DailyEnsembleForecastResponse, anchorTime: Double) {
        let windSetting = WindSpeedUnit(settingValue: SettingService.shared.windSpeedUnit)
        timeZone = response.timeZone
        utcOffsetSeconds = response.utcOffsetSeconds
        isFahrenheit = response.dailyUnits["temperature_2m_max"]?.contains("F") ?? false
        precipitationUnit = response.dailyUnits["precipitation_sum"] ?? "mm"
        usesBeaufort = windSetting.usesBeaufortDisplay
        windUnit = usesBeaufort ? windSetting.displayUnit : response.dailyUnits["wind_speed_10m_max"] ?? "km/h"
        days = response.days
        selectedIndex = days.indices.min { abs(days[$0].noon - anchorTime) < abs(days[$1].noon - anchorTime) } ?? 0
    }

    func select(atFraction fraction: Double) {
        guard !days.isEmpty else { return }
        let index = min(max(Int(fraction * Double(days.count)), 0), days.count - 1)
        if index != selectedIndex { selectedIndex = index }
    }

    func step(by offset: Int) {
        guard !days.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), days.count - 1)
    }

    func spread(_ lens: EnsembleLens, of day: EnsembleDay) -> EnsembleSpread? {
        switch lens {
        case .sky: nil
        case .high: day.high
        case .low: day.low
        case .precipitation: day.precipitation
        case .wind: usesBeaufort ? day.wind?.map { BeaufortScale.value(forKilometersPerHour: $0) ?? 0 } : day.wind
        }
    }

    func number(_ value: Double, for lens: EnsembleLens) -> String {
        switch lens {
        case .precipitation:
            let digits = precipitationUnit == "inch" ? 0...2 : (value < 10 ? 0...1 : 0...0)
            return value.formatted(.number.precision(.fractionLength(digits)))
        default:
            let rounded = Int(value.rounded())
            return rounded < 0 ? "−\(-rounded)" : "\(rounded)"
        }
    }

    func range(_ low: Double, _ high: Double, for lens: EnsembleLens) -> String {
        let from = number(low, for: lens)
        let to = number(high, for: lens)
        return (from == to ? from : from + "–" + to) + unitSuffix(for: lens)
    }

    func formatted(_ value: Double, for lens: EnsembleLens) -> String {
        number(value, for: lens) + unitSuffix(for: lens)
    }

    private func unitSuffix(for lens: EnsembleLens) -> String {
        switch lens {
        case .sky: ""
        case .high, .low: "°"
        case .precipitation: " " + precipitationUnit
        case .wind: " " + windUnit
        }
    }

    func rowValue(for lens: EnsembleLens) -> String {
        guard let day = selectedDay else { return "--" }
        if lens == .sky {
            guard let dominant = day.sky.dominant else { return "--" }
            return dominant.title + " " + day.sky.share(of: dominant).formatted(.percent.precision(.fractionLength(0)))
        }
        guard let spread = spread(lens, of: day) else { return "--" }
        return range(spread.low, spread.high, for: lens)
    }

    var eyebrowLabel: String {
        guard let day = selectedDay else { return "" }
        let date = Date(timeIntervalSince1970: day.noon)
        return HourlyFormatting.dayLabel(timestamp: day.noon, timeZone: timeZone, now: .now)
            + " · " + SettingService.formattedDayMonth(date, timeZone: timeZone)
    }

    var titleLabel: String {
        guard let day = selectedDay else { return "" }
        return EnsembleConfidence(day: day, fahrenheit: isFahrenheit).title
    }

    var footnote: String {
        guard let day = selectedDay else { return "" }
        return String(localized: "So einig ist sich die Vorhersage. Bei schmalem Band sagen fast alle Berechnungen dasselbe, bei breitem kann der Tag noch so oder so ausgehen.")
    }

    func shortDateLabel(_ day: EnsembleDay) -> String {
        let date = Date(timeIntervalSince1970: day.noon)
        return SettingService.formattedShortWeekday(date, timeZone: timeZone)
            + " " + SettingService.formattedDayMonth(date, timeZone: timeZone)
    }

    func axisLabels(columnWidth: CGFloat) -> [(index: Int, text: String)] {
        let every = columnWidth >= 22 ? 1 : (columnWidth >= 12 ? 2 : 7)
        return stride(from: 0, to: days.count, by: every).map { index in
            let date = Date(timeIntervalSince1970: days[index].noon)
            let text = every == 7
                ? SettingService.formattedDayMonth(date, timeZone: timeZone)
                : SettingService.formattedShortWeekday(date, timeZone: timeZone)
            return (index, text)
        }
    }

    func accessibilityValue(for lens: EnsembleLens) -> String {
        guard let day = selectedDay else { return "" }
        return shortDateLabel(day) + ", " + rowValue(for: lens) + ", " + titleLabel
    }
}

extension AtmosphereWeatherMapper {
    /// A day's consensus sky at local noon: the weather most runs agree on.
    static func snapshot(
        for day: EnsembleDay,
        at location: CLLocationCoordinate2D,
        utcOffsetSeconds: Int
    ) -> AtmosphereSnapshot {
        let condition = conditionFamily(for: day.sky.dominantCode ?? 0)
        let isWet = day.sky.dominant == .rain || day.sky.dominant == .snow
        let cloudCoverage = max(clamp(Float(day.cloudCover ?? 0) / 100, 0, 1), isWet ? 0.75 : 0)
        let intensity = isWet ? clamp(Float(day.precipitation?.median ?? 0) / 15, 0.15, 1) : 0
        var deck = CloudDeck(total: cloudCoverage)
        reconcile(&deck, total: cloudCoverage, condition: condition)
        return finalize(
            utcOffsetSeconds: utcOffsetSeconds,
            aqiHaze: 0,
            location: location,
            timestamp: day.noon,
            condition: condition,
            cloudCoverage: cloudCoverage,
            humidity: 0.6,
            precipitation: intensity * 8,
            snowfall: Float(day.snowfall ?? 0),
            precipitationIntensity: intensity,
            windSpeed: Float(day.wind?.median ?? 0),
            windDirection: 0,
            deck: deck
        )
    }
}
