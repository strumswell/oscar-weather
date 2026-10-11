import SwiftUI

/// The blocks of the forecast page below the head, shown in the order the
/// user keeps them (`SettingService.nowSections`; absent = hidden). The map
/// only exists on the wide page's stage; the phone page skips it.
enum NowSection: String, CaseIterable, Identifiable {
    case map, radar, hourly, daily, stations, environment, climate

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .map: "Karte"
        case .radar: "Radar"
        case .hourly: "Stündlich"
        case .daily: "Täglich"
        case .environment: "Umwelt"
        case .climate: "Klima"
        case .stations: "Messstationen"
        }
    }

    var systemImage: String {
        switch self {
        case .map: "map"
        case .radar: "cloud.rain"
        case .hourly: "clock"
        case .daily: "calendar"
        case .environment: "leaf"
        case .climate: "chart.bar.xaxis"
        case .stations: "sensor"
        }
    }

    /// Settings tile color; a fixed hue per section so rows read at a glance.
    var tint: Color {
        switch self {
        case .map: .cyan
        case .radar: .blue
        case .hourly: .orange
        case .daily: .indigo
        case .environment: .green
        case .climate: .red
        case .stations: .teal
        }
    }

    /// The live section. Only the radar teaser needs a way onto the map;
    /// `isWide` lets the daily list open days in place. The map takes the
    /// stage's spare height.
    @MainActor @ViewBuilder
    func view(openRadarMap: @escaping () -> Void = {}, isWide: Bool = false) -> some View {
        switch self {
        case .map: MapPreview().frame(minHeight: 240, maxHeight: .infinity)
        case .radar: RainView(openRadarMap: openRadarMap)
        case .hourly: HourlyView()
        case .daily: DailyView(expandsDays: isWide)
        case .environment: EnvironmentGaugesView()
        case .climate: ClimateView()
        case .stations: StationsView()
        }
    }
}

/// The wide forecast (iPad, the Duo's inner display in landscape, Mac
/// windows) splits the page into the stage on the left and the feed on the
/// right; the user picks which sections go where.
enum WideForecast {
    static let minWidth: CGFloat = 760
    static let defaultStage: Set<NowSection> = [.map, .radar, .stations]

    /// Phone-sized cards: half the window, between 380 and 640 pt.
    static func feedWidth(for width: CGFloat) -> CGFloat {
        min(640, max(380, width / 2))
    }
}

extension SettingService {
    /// Every section in the user's order. Sections missing from the stored
    /// order (new ones) fall in right after their default predecessor.
    var nowSectionOrder: [NowSection] {
        get {
            var order = (nowSectionOrderRaw ?? []).compactMap(NowSection.init(rawValue:))
            for section in NowSection.allCases where !order.contains(section) {
                let predecessor = NowSection.allCases.prefix { $0 != section }.last { order.contains($0) }
                order.insert(section, at: predecessor.flatMap { order.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
            }
            return order
        }
        set { nowSectionOrderRaw = newValue.map(\.rawValue) }
    }

    var hiddenNowSections: Set<NowSection> {
        get { Set((hiddenNowSectionsRaw ?? []).compactMap(NowSection.init(rawValue:))) }
        set { hiddenNowSectionsRaw = newValue.map(\.rawValue).sorted() }
    }

    /// The sections on the wide page's left column.
    var stageNowSections: Set<NowSection> {
        get { stageNowSectionsRaw.map { Set($0.compactMap(NowSection.init(rawValue:))) } ?? WideForecast.defaultStage }
        set { stageNowSectionsRaw = newValue.map(\.rawValue).sorted() }
    }

    /// What the forecast page shows, in order.
    var nowSections: [NowSection] {
        nowSectionOrder.filter { !hiddenNowSections.contains($0) }
    }

    /// The phone page: everything but the map.
    var nowPageSections: [NowSection] {
        nowSections.filter { $0 != .map }
    }

    var nowStageSections: [NowSection] {
        nowSections.filter { stageNowSections.contains($0) }
    }

    var nowFeedSections: [NowSection] {
        nowSections.filter { !stageNowSections.contains($0) }
    }
}
