import Foundation

enum RainNowcastSummary {
    static let horizon: TimeInterval = 90 * 60
    static let maxBars = 18

    static func points(from series: PrecipSeriesResponse?, now: Date) -> [PrecipPoint] {
        guard let series else { return [] }
        return Array(series.series
            .filter { $0.timestamp > now.addingTimeInterval(-150) && $0.timestamp <= now.addingTimeInterval(horizon) }
            .sorted { $0.timestamp < $1.timestamp }
            .prefix(maxBars))
    }

    static func headline(for points: [PrecipPoint], now: Date, timeZone: TimeZone = .current) -> String {
        let isRainingNow = (points.first?.precipitation ?? 0) > 0

        if isRainingNow {
            if let end = points.first(where: { $0.precipitation <= 0 }) {
                let minutes = max(5, Int((end.timestamp.timeIntervalSince(now) / 60).rounded()))
                if minutes <= 60 {
                    return String(localized: "Regen · noch ~\(minutes) min")
                }
                return String(localized: "Regen bis \(SettingService.formattedTime(end.timestamp, timeZone: timeZone))")
            }
            let last = points.last?.timestamp ?? now
            let minutes = max(5, Int((last.timeIntervalSince(now) / 60).rounded()))
            return String(localized: "Regen · noch >\(minutes) min")
        }

        if let start = points.first(where: { $0.precipitation > 0 }) {
            return String(localized: "Regen ab \(SettingService.formattedTime(start.timestamp, timeZone: timeZone))")
        }
        return String(localized: "Kein Regen in Sicht")
    }

    static func shortHeadline(for points: [PrecipPoint], timeZone: TimeZone = .current) -> String {
        if (points.first?.precipitation ?? 0) > 0 {
            guard let end = points.first(where: { $0.precipitation <= 0 }) else { return String(localized: "Regen") }
            return String(localized: "bis \(SettingService.formattedTime(end.timestamp, timeZone: timeZone))")
        }
        if let start = points.first(where: { $0.precipitation > 0 }) {
            return String(localized: "ab \(SettingService.formattedTime(start.timestamp, timeZone: timeZone))")
        }
        return String(localized: "Trocken")
    }

    static func spokenHeadline(for points: [PrecipPoint], now: Date, timeZone: TimeZone = .current) -> String {
        let isRainingNow = (points.first?.precipitation ?? 0) > 0

        if isRainingNow {
            if let end = points.first(where: { $0.precipitation <= 0 }) {
                let minutes = max(5, Int((end.timestamp.timeIntervalSince(now) / 60).rounded()))
                if minutes <= 60 {
                    return String(localized: "Es regnet noch etwa \(minutes) Minuten.")
                }
                return String(localized: "Es regnet bis \(SettingService.formattedTime(end.timestamp, timeZone: timeZone)).")
            }
            let last = points.last?.timestamp ?? now
            let minutes = max(5, Int((last.timeIntervalSince(now) / 60).rounded()))
            return String(localized: "Es regnet noch mindestens \(minutes) Minuten.")
        }

        if let start = points.first(where: { $0.precipitation > 0 }) {
            return String(localized: "Ab \(SettingService.formattedTime(start.timestamp, timeZone: timeZone)) regnet es.")
        }
        return String(localized: "Kein Regen in Sicht.")
    }

    static func values(_ points: [PrecipPoint]) -> [Double] {
        points.map { max(0, $0.precipitation) }
    }

    static func peak(in points: [PrecipPoint]) -> PrecipPoint? {
        points.filter { $0.precipitation > 0 }.max { $0.precipitation < $1.precipitation }
    }

    static let sampleComing: [Double] = [0, 0, 0, 0, 0, 0, 0.2, 0.6, 1.2, 2.4, 3.5, 2.8, 1.6, 0.9, 0.5, 0.3, 0.2, 0.1]
    static let sampleRaining: [Double] = [2.1, 2.6, 3.4, 4.8, 3.9, 2.7, 1.8, 1.1, 0.6, 0.3, 0.1, 0, 0, 0, 0, 0, 0, 0]

    static func samplePoints(_ values: [Double], now: Date) -> [PrecipPoint] {
        values.enumerated().map { step, precipitation in
            PrecipPoint(timestamp: now.addingTimeInterval(Double(step) * 300), precipitation: precipitation, isForecast: step > 0)
        }
    }
}
