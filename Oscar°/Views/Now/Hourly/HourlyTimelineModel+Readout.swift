import SwiftUI

extension HourlyTimelineModel {
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
        return day + " " + SettingService.formattedDayMonth(Date(timeIntervalSince1970: scrubTime), timeZone: timeZone)
    }

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
        return HourlyFormatting.windString(
            speed,
            unit: WindSpeedUnit(settingValue: SettingService.shared.windSpeedUnit),
            unitString: windUnitString
        )
    }

    /// Formatted like the lens' chart labels so row and chart never disagree.
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
    var compactMoistureUnit: String {
        soilMoistureUnit.replacingOccurrences(of: "/", with: "\u{2044}")
    }

    var accessibilityValue: String {
        guard hasData else { return "" }
        return timeLabel + ", " + temperatureLabel + ", " + conditionLabel
            + ", " + String(localized: "Wind") + " " + windLabel
    }
}
