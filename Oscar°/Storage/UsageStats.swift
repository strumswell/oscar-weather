import Foundation

/// On-device usage statistics: the raw material for the stats page. Never
/// leaves the device except into the user's own iCloud key-value store, one
/// blob per install, summed on display.
struct UsageStats: Codable {
    struct Extreme: Codable {
        var value: Double
        var unit: String
        var date: Date
        var place: String
    }

    // New fields must be optional so an older install's blob still decodes.
    var firstLaunch = Date.now
    var opens = 0
    var activeSeconds = 0.0
    var longestSessionSeconds = 0.0
    var opensByHour = Array(repeating: 0, count: 24)
    /// Index 0 = Sunday, `Calendar.component(.weekday)` minus one.
    var opensByWeekday = Array(repeating: 0, count: 7)
    /// "yyyy-MM-dd" → opens that day.
    var dailyOpens: [String: Int] = [:]
    var sheets: [String: Int] = [:]
    var tabs: [String: Int] = [:]
    var notificationsShown = 0
    var notificationsOpened = 0
    /// Network requests per API host, cache hits excluded.
    var apiCalls: [String: Int] = [:]
    var scrolledPoints = 0.0
    var places: [String: Int] = [:]
    var hottest: Extreme?
    var coldest: Extreme?
    var windiest: Extreme?
    var wettest: Extreme?
    var highestUV: Extreme?
    var supporterSince: Date?

    var activeDays: Int { dailyOpens.count }

    /// iPhone logical density: 163 points per inch.
    var scrolledMeters: Double { scrolledPoints / 163 * 0.0254 }

    /// Sums another install's blob into this one.
    // ponytail: extremes compare raw values across units; two devices on °C and °F
    // would mix. Convert to a base unit if that ever matters.
    mutating func merge(_ other: UsageStats) {
        firstLaunch = min(firstLaunch, other.firstLaunch)
        opens += other.opens
        activeSeconds += other.activeSeconds
        longestSessionSeconds = max(longestSessionSeconds, other.longestSessionSeconds)
        opensByHour = zip(opensByHour, other.opensByHour).map(+)
        opensByWeekday = zip(opensByWeekday, other.opensByWeekday).map(+)
        dailyOpens.merge(other.dailyOpens, uniquingKeysWith: +)
        sheets.merge(other.sheets, uniquingKeysWith: +)
        tabs.merge(other.tabs, uniquingKeysWith: +)
        notificationsShown += other.notificationsShown
        notificationsOpened += other.notificationsOpened
        apiCalls.merge(other.apiCalls, uniquingKeysWith: +)
        scrolledPoints += other.scrolledPoints
        places.merge(other.places, uniquingKeysWith: +)
        hottest = Self.higher(hottest, other.hottest)
        coldest = Self.lower(coldest, other.coldest)
        windiest = Self.higher(windiest, other.windiest)
        wettest = Self.higher(wettest, other.wettest)
        highestUV = Self.higher(highestUV, other.highestUV)
        if let theirs = other.supporterSince {
            supporterSince = min(supporterSince ?? theirs, theirs)
        }
    }

    /// The extreme with the higher value; a missing side loses.
    static func higher(_ a: Extreme?, _ b: Extreme?) -> Extreme? {
        guard let a else { return b }
        guard let b else { return a }
        return b.value > a.value ? b : a
    }

    static func lower(_ a: Extreme?, _ b: Extreme?) -> Extreme? {
        guard let a else { return b }
        guard let b else { return a }
        return b.value < a.value ? b : a
    }
}
