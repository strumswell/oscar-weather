import Foundation
import Observation

@MainActor
@Observable
final class UsageStatsStore {
    static let shared = UsageStatsStore()

    private(set) var stats: UsageStats
    /// Blobs of other installs, pulled from iCloud.
    private(set) var otherInstalls: [UsageStats] = []

    @ObservationIgnored private var sessionStart: Date?
    @ObservationIgnored private var pendingScroll = 0.0
    @ObservationIgnored private var unsavedChanges = 0
    @ObservationIgnored private let installID: String
    @ObservationIgnored private let cloud = NSUbiquitousKeyValueStore.default

    private static let key = "usageStats"
    private static let installIDKey = "usageStatsInstallID"
    private static let cloudPrefix = "stats."

    private init() {
        let defaults = AppGroup.defaults
        stats = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(UsageStats.self, from: $0) } ?? UsageStats()
        if let id = defaults.string(forKey: Self.installIDKey) {
            installID = id
        } else {
            installID = UUID().uuidString
            defaults.set(installID, forKey: Self.installIDKey)
        }
        cloud.synchronize()
        loadOtherInstalls()
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { _ in
            Task { @MainActor in UsageStatsStore.shared.loadOtherInstalls() }
        }
    }

    /// Everything across all installs, for display.
    var combined: UsageStats {
        var total = stats
        for other in otherInstalls {
            total.merge(other)
        }
        return total
    }

    func record(_ mutate: (inout UsageStats) -> Void) {
        guard !ScreenshotMode.active else { return }
        mutate(&stats)
        unsavedChanges += 1
        if unsavedChanges >= 30 { flush() }
    }

    func sceneDidActivate() {
        guard sessionStart == nil else { return }
        let now = Date.now
        sessionStart = now
        let calendar = Calendar.current
        record {
            $0.opens += 1
            $0.opensByHour[calendar.component(.hour, from: now)] += 1
            $0.opensByWeekday[calendar.component(.weekday, from: now) - 1] += 1
            $0.dailyOpens[Self.dayKey(now), default: 0] += 1
        }
    }

    func sceneDidEnterBackground() {
        guard let sessionStart else { return }
        let seconds = Date.now.timeIntervalSince(sessionStart)
        self.sessionStart = nil
        record {
            $0.activeSeconds += seconds
            $0.longestSessionSeconds = max($0.longestSessionSeconds, seconds)
        }
        flush()
    }

    /// Called per scroll frame; folded into the blob on the next flush.
    func addScroll(points: Double) {
        pendingScroll += points
    }

    /// Values arrive in the units the forecast was requested in.
    func recordConditions(temperature: Double?, wind: Double?, precipitation: Double?, uv: Double?, place: String) {
        let settings = SettingService.shared
        let temperatureUnit = settings.temperatureUnit == "fahrenheit" ? "°F" : "°C"
        let windSetting = WindSpeedUnit(settingValue: SettingService.resolvedWindSpeedUnit)
        // Beaufort is derived on device; the API delivers km/h for it.
        let windUnit = windSetting == .bft ? "km/h" : windSetting.displayUnit
        let precipitationUnit = settings.precipitationUnit == "inch" ? "in" : "mm"

        let now = Date.now
        func extreme(_ value: Double?, _ unit: String) -> UsageStats.Extreme? {
            guard let value else { return nil }
            return UsageStats.Extreme(value: value, unit: unit, date: now, place: place)
        }

        record {
            if !place.isEmpty {
                $0.places[place, default: 0] += 1
            }
            $0.hottest = UsageStats.higher($0.hottest, extreme(temperature, temperatureUnit))
            $0.coldest = UsageStats.lower($0.coldest, extreme(temperature, temperatureUnit))
            $0.windiest = UsageStats.higher($0.windiest, extreme(wind, windUnit))
            if let precipitation, precipitation > 0 {
                $0.wettest = UsageStats.higher($0.wettest, extreme(precipitation, precipitationUnit))
            }
            $0.highestUV = UsageStats.higher($0.highestUV, extreme(uv, ""))
        }
    }

    func flush() {
        if pendingScroll > 0, !ScreenshotMode.active {
            stats.scrolledPoints += pendingScroll
        }
        pendingScroll = 0
        unsavedChanges = 0
        guard let data = try? JSONEncoder().encode(stats) else { return }
        AppGroup.defaults.set(data, forKey: Self.key)
        cloud.set(data, forKey: Self.cloudPrefix + installID)
    }

    private func loadOtherInstalls() {
        let decoder = JSONDecoder()
        let own = Self.cloudPrefix + installID
        otherInstalls = cloud.dictionaryRepresentation.compactMap { key, value in
            guard key.hasPrefix(Self.cloudPrefix), key != own, let data = value as? Data else { return nil }
            return try? decoder.decode(UsageStats.self, from: data)
        }
    }

    static func dayKey(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }
}
