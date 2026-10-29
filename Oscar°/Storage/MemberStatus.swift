import Foundation
import StoreKit

enum MemberTier: String, CaseIterable, Comparable {
    case member, supporter, founder, founderSupporter

    static func < (lhs: MemberTier, rhs: MemberTier) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    var isFounder: Bool { self == .founder || self == .founderSupporter }
    var isSupporter: Bool { self == .supporter || self == .founderSupporter }

    var name: String {
        switch self {
        case .member: "Member"
        case .supporter: "Supporter"
        case .founder, .founderSupporter: "Founder"
        }
    }

    var styleName: String {
        self == .founderSupporter ? "Founder + Supporter" : name
    }

    func allows(_ style: MemberTier) -> Bool {
        (isFounder || !style.isFounder) && (isSupporter || !style.isSupporter)
    }

    var styles: [MemberTier] {
        Self.allCases.filter(allows)
    }
}

struct MemberTitle: Identifiable, Sendable {
    let id: String
    let name: LocalizedStringResource
    let rule: @Sendable (Units) -> LocalizedStringResource
    let isEarned: @Sendable (UsageStats) -> Bool

    static let all: [MemberTitle] = [
        MemberTitle(id: "Minus 20 Club", name: "Minus-20-Club", rule: { "\($0.temperatureString(-20)) oder kälter erlebt" }) {
            ($0.coldest?.canonical.value ?? 0) <= -20
        },
        MemberTitle(id: "Storm Watcher", name: "Sturmwache", rule: { "Wind ab \($0.windString(100)) erlebt" }) {
            ($0.windiest?.canonical.value ?? 0) >= 100
        },
        MemberTitle(id: "Heatwave", name: "Hitzewelle", rule: { "\($0.temperatureString(35)) oder heißer erlebt" }) {
            ($0.hottest?.canonical.value ?? 0) >= 35
        },
        MemberTitle(id: "Cloudburst", name: "Wolkenbruch", rule: { "Regen ab \($0.precipitationString(30)) erlebt" }) {
            ($0.wettest?.canonical.value ?? 0) >= 30
        },
        MemberTitle(id: "UV 10", name: "UV 10", rule: { _ in "UV-Index 10 oder höher erlebt" }) {
            ($0.highestUV?.value ?? 0) >= 10
        },
        MemberTitle(id: "Daily", name: "Täglich", rule: { _ in "100 Tage am Stück dabei" }) {
            $0.streaks().longest >= 100
        },
        MemberTitle(id: "Globetrotter", name: "Globetrotter", rule: { _ in "Wetter für 10 Orte angesehen" }) {
            $0.places.count >= 10
        },
        MemberTitle(id: "Regular", name: "Stammgast", rule: { _ in "30 Tage am Stück dabei" }) {
            $0.streaks().longest >= 30
        },
        MemberTitle(id: "Radar Regular", name: "Radar-Stammgast", rule: { _ in "Karten 500-mal geöffnet" }) {
            $0.tabs["maps", default: 0] >= 500
        },
        MemberTitle(id: "Cat Person", name: "Katzenmensch", rule: { _ in "100-mal mit dem Kater gespielt" }) {
            ($0.cat?.values.reduce(0, +) ?? 0) >= 100
        },
        MemberTitle(id: "Night Owl", name: "Nachteule", rule: { _ in "Meist zwischen 22 und 2 Uhr hier" }) {
            peakHour(of: $0).map { [22, 23, 0, 1].contains($0) } ?? false
        },
        MemberTitle(id: "Early Riser", name: "Früher Vogel", rule: { _ in "Meist zwischen 5 und 8 Uhr hier" }) {
            peakHour(of: $0).map { (5..<8).contains($0) } ?? false
        },
    ]

    static func earned(in stats: UsageStats) -> [MemberTitle] {
        all.filter { $0.isEarned(stats) }
    }

    static func displayName(for id: String) -> String {
        all.first { $0.id == id }.map { String(localized: $0.name) } ?? id
    }

    private static func peakHour(of stats: UsageStats) -> Int? {
        guard stats.opens >= 20, let peak = stats.opensByHour.max(), peak > 0 else { return nil }
        return stats.opensByHour.firstIndex(of: peak)
    }
}

struct MemberStatus: Equatable {
    static let titleKey = "memberCardTitle"
    static let styleKey = "memberCardStyle"

    var tier: MemberTier
    var style: MemberTier
    var since: Date
    var years: Int
    var title: String?
    var earnedTitles: [String]

    init(stats: UsageStats, isSupporter: Bool, chosenTitle: String?, chosenStyle: MemberTier? = nil, unlocks: ClubUnlocks = .none, now: Date = .now) {
        let supporter = isSupporter || stats.supporterSince != nil || unlocks.supporter
        let tier: MemberTier = if stats.testFlightSince != nil || unlocks.founder {
            supporter ? .founderSupporter : .founder
        } else {
            supporter ? .supporter : .member
        }
        self.tier = tier
        style = chosenStyle.flatMap { tier.allows($0) ? $0 : nil } ?? tier
        since = [stats.firstLaunch, stats.testFlightSince, stats.supporterSince].compactMap { $0 }.min() ?? now
        let natural = max(0, Calendar.current.dateComponents([.year], from: since, to: now).year ?? 0)
        years = max(unlocks.years ?? 0, natural)
        earnedTitles = MemberTitle.earned(in: stats).map(\.id) + unlocks.titles
        title = chosenTitle == "" ? nil : (earnedTitles.first { $0 == chosenTitle } ?? earnedTitles.first)
    }

    @MainActor static func current() -> MemberStatus {
        let defaults = UserDefaults.standard
        return MemberStatus(
            stats: UsageStatsStore.shared.combined,
            isSupporter: SupporterStore.shared.isSupporter,
            chosenTitle: defaults.string(forKey: titleKey),
            chosenStyle: defaults.string(forKey: styleKey).flatMap(MemberTier.init),
            unlocks: ClubRewardStore.shared.unlocks
        )
    }
}

enum TestFlightMembership {
    static let publicReleaseDate: Date? = nil

    @MainActor static var isTestFlight = false

    @MainActor static var showsLab: Bool {
        #if DEBUG
        true
        #else
        isTestFlight
        #endif
    }

    @MainActor
    static func stampIfNeeded() async {
        guard case .verified(let transaction)? = try? await AppTransaction.shared,
              transaction.environment == .sandbox else { return }
        isTestFlight = true
        if let publicReleaseDate, Date.now >= publicReleaseDate { return }
        let joined = UsageStatsStore.shared.combined.firstLaunch
        if let known = UsageStatsStore.shared.stats.testFlightSince, known <= joined { return }
        UsageStatsStore.shared.record { $0.testFlightSince = joined }
        UsageStatsStore.shared.flush()
    }
}
