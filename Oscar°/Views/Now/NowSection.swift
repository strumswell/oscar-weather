import SwiftUI

enum NowSection: String, CaseIterable, Identifiable, Codable {
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

    func renders(wide: Bool) -> Bool {
        switch self {
        case .map: wide
        case .hourly: !wide
        default: true
        }
    }

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

enum WideForecast {
    static let minWidth: CGFloat = 760
    static let defaultStage: Set<NowSection> = [.map, .radar, .stations]

    static let maxColumnWidth: CGFloat = 720
}

enum LayoutForm: String, CaseIterable {
    case compact, widePortrait, wideLandscape

    static func of(_ size: CGSize) -> LayoutForm {
        if size.width < WideForecast.minWidth { .compact } else if size.width > size.height { .wideLandscape } else { .widePortrait }
    }

    var isWide: Bool { self != .compact }
}

struct SectionArrangement: Codable, Equatable {
    var order: [NowSection]
    var hidden: Set<NowSection>
    var stage: Set<NowSection>

    static let `default` = SectionArrangement(order: NowSection.allCases, hidden: [], stage: WideForecast.defaultStage)

    var visible: [NowSection] { order.filter { !hidden.contains($0) } }

    var pageSections: [NowSection] { visible.filter { $0.renders(wide: false) } }

    var stageSections: [NowSection] { visible.filter { $0.renders(wide: true) && stage.contains($0) } }

    var feedSections: [NowSection] { visible.filter { $0.renders(wide: true) && !stage.contains($0) } }

    var completed: SectionArrangement {
        var copy = self
        for section in NowSection.allCases where !copy.order.contains(section) {
            let predecessor = NowSection.allCases.prefix { $0 != section }.last { copy.order.contains($0) }
            copy.order.insert(section, at: predecessor.flatMap { copy.order.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        }
        return copy
    }

    mutating func place(_ section: NowSection, at index: Int, among column: [NowSection], onStage: Bool?) {
        order.removeAll { $0 == section }
        let column = column.filter { $0 != section }
        hidden.remove(section)
        if let onStage, section != .map {
            if onStage { stage.insert(section) } else { stage.remove(section) }
        }
        if column.isEmpty {
            onStage == true ? order.insert(section, at: 0) : order.append(section)
        } else if index < column.count, let slot = order.firstIndex(of: column[index]) {
            order.insert(section, at: slot)
        } else if let last = column.last, let slot = order.firstIndex(of: last) {
            order.insert(section, at: slot + 1)
        }
    }
}

extension SettingService {
    func arrangement(for form: LayoutForm) -> SectionArrangement {
        if let data = sectionArrangementsRaw[form.rawValue],
           let stored = try? JSONDecoder().decode(SectionArrangement.self, from: data) {
            return stored.completed
        }
        return SectionArrangement(
            order: (nowSectionOrderRaw ?? []).compactMap(NowSection.init(rawValue:)),
            hidden: Set((hiddenNowSectionsRaw ?? []).compactMap(NowSection.init(rawValue:))),
            stage: stageNowSectionsRaw.map { Set($0.compactMap(NowSection.init(rawValue:))) } ?? WideForecast.defaultStage
        ).completed
    }

    func setArrangement(_ arrangement: SectionArrangement, for form: LayoutForm) {
        sectionArrangementsRaw[form.rawValue] = try? JSONEncoder().encode(arrangement)
    }

    var arrangementsAreDefault: Bool {
        LayoutForm.allCases.allSatisfy { arrangement(for: $0) == .default }
    }

    func resetArrangements() {
        sectionArrangementsRaw = [:]
        nowSectionOrderRaw = nil
        hiddenNowSectionsRaw = nil
        stageNowSectionsRaw = nil
    }
}
