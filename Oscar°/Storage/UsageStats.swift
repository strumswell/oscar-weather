import Foundation

enum CatStat: String, CaseIterable {
    case fish, kicks, catches, scratches, pets, naps
}

struct UsageStats: Codable {
    struct Extreme: Codable {
        var value: Double
        var unit: String
        var date: Date
        var place: String

        static func dimension(_ symbol: String) -> Dimension? {
            switch symbol {
            case "°C": UnitTemperature.celsius
            case "°F": UnitTemperature.fahrenheit
            case "km/h": UnitSpeed.kilometersPerHour
            case "m/s": UnitSpeed.metersPerSecond
            case "mph": UnitSpeed.milesPerHour
            case "kn": UnitSpeed.knots
            case "mm": UnitLength.millimeters
            case "in", "inch": UnitLength.inches
            default: nil
            }
        }

        func converted(to symbol: String) -> Extreme {
            guard symbol != unit,
                  let from = Self.dimension(unit),
                  let to = Self.dimension(symbol),
                  ObjectIdentifier(type(of: from)) == ObjectIdentifier(type(of: to))
            else { return self }
            var copy = self
            copy.value = Measurement(value: value, unit: from).converted(to: to).value
            copy.unit = symbol
            return copy
        }

        var canonical: Extreme {
            switch Self.dimension(unit) {
            case is UnitTemperature: converted(to: "°C")
            case is UnitSpeed: converted(to: "km/h")
            case is UnitLength: converted(to: "mm")
            default: self
            }
        }
    }

    // New fields must be optional so an older install's blob still decodes.
    var firstLaunch = Date.now
    var opens = 0
    var activeSeconds = 0.0
    var longestSessionSeconds = 0.0
    var opensByHour = Array(repeating: 0, count: 24)
    var opensByWeekday = Array(repeating: 0, count: 7)
    var dailyOpens: [String: Int] = [:]
    var sheets: [String: Int] = [:]
    var tabs: [String: Int] = [:]
    var notificationsShown = 0
    var notificationsOpened = 0
    var apiCalls: [String: Int] = [:]
    var scrolledPoints = 0.0
    var places: [String: Int] = [:]
    var hottest: Extreme?
    var coldest: Extreme?
    var windiest: Extreme?
    var wettest: Extreme?
    var highestUV: Extreme?
    var supporterSince: Date?
    var testFlightSince: Date?
    var cat: [String: Int]?

    var activeDays: Int { dailyOpens.count }

    var scrolledMeters: Double { scrolledPoints / 163 * 0.0254 }

    func streaks(now: Date = .now) -> (current: Int, longest: Int) {
        let style = Date.ISO8601FormatStyle().year().month().day()
        let day: TimeInterval = 86_400
        let days = Set(dailyOpens.keys.compactMap { try? Date($0, strategy: style) })
        var longest = 0
        for start in days where !days.contains(start - day) {
            var length = 1
            while days.contains(start + Double(length) * day) { length += 1 }
            longest = max(longest, length)
        }
        guard var cursor = try? Date(now.formatted(style), strategy: style) else { return (0, longest) }
        if !days.contains(cursor) { cursor -= day }
        var current = 0
        while days.contains(cursor) {
            current += 1
            cursor -= day
        }
        return (current, longest)
    }

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
        if let theirs = other.cat {
            cat = (cat ?? [:]).merging(theirs, uniquingKeysWith: +)
        }
        hottest = Self.higher(hottest, other.hottest)
        coldest = Self.lower(coldest, other.coldest)
        windiest = Self.higher(windiest, other.windiest)
        wettest = Self.higher(wettest, other.wettest)
        highestUV = Self.higher(highestUV, other.highestUV)
        if let theirs = other.supporterSince {
            supporterSince = min(supporterSince ?? theirs, theirs)
        }
        if let theirs = other.testFlightSince {
            testFlightSince = min(testFlightSince ?? theirs, theirs)
        }
    }

    static func higher(_ a: Extreme?, _ b: Extreme?) -> Extreme? {
        guard let a = a?.canonical else { return b?.canonical }
        guard let b = b?.canonical else { return a }
        return b.value > a.value ? b : a
    }

    static func lower(_ a: Extreme?, _ b: Extreme?) -> Extreme? {
        guard let a = a?.canonical else { return b?.canonical }
        guard let b = b?.canonical else { return a }
        return b.value < a.value ? b : a
    }
}
