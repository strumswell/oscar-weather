import SwiftUI

/// The blocks of the forecast page below the head, shown in the order the
/// user keeps them (`SettingService.nowSections`; absent = hidden).
enum NowSection: String, CaseIterable, Identifiable {
    case radar, hourly, daily, environment, climate

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .radar: "Radar"
        case .hourly: "Stündlich"
        case .daily: "Täglich"
        case .environment: "Umwelt"
        case .climate: "Klima"
        }
    }

    var systemImage: String {
        switch self {
        case .radar: "cloud.rain"
        case .hourly: "clock"
        case .daily: "calendar"
        case .environment: "leaf"
        case .climate: "chart.bar.xaxis"
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
        }
    }
}

extension SettingService {
    /// Every section in the user's order. Sections missing from the stored
    /// order (new ones) fall in at the end.
    var nowSectionOrder: [NowSection] {
        get {
            let stored = (nowSectionOrderRaw ?? []).compactMap(NowSection.init(rawValue:))
            return stored + NowSection.allCases.filter { !stored.contains($0) }
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
