import SwiftUI

/// The blocks of the forecast page below the head, shown in the order the
/// user keeps them (`SettingService.nowSections`; absent = hidden).
enum NowSection: String, CaseIterable, Identifiable {
    case radar, hourly, daily, stations, environment, climate

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
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
        case .radar: .blue
        case .hourly: .orange
        case .daily: .indigo
        case .environment: .green
        case .climate: .red
        case .stations: .teal
        }
    }

    /// The live section. Only the radar teaser needs a way onto the map.
    @MainActor @ViewBuilder
    func view(openRadarMap: @escaping () -> Void = {}) -> some View {
        switch self {
        case .radar: RainView(openRadarMap: openRadarMap)
        case .hourly: HourlyView()
        case .daily: DailyView()
        case .environment: EnvironmentGaugesView()
        case .climate: ClimateView()
        case .stations: StationsView()
        }
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

    /// What the forecast page shows, in order.
    var nowSections: [NowSection] {
        nowSectionOrder.filter { !hiddenNowSections.contains($0) }
    }
}
