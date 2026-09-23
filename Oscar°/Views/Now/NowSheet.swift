import Foundation

enum NowSheet: Identifiable {
    case hourly(Date?)
    case daily
    case environment(EnvironmentDetailSection)
    case climate(ClimateSummary)
    case stations(String)
    case alerts
    case settings
    case layout

    var id: String {
        switch self {
        case .hourly:
            "hourly"
        case .daily:
            "daily"
        case .environment(let section):
            "environment-\(section.rawValue)"
        case .climate:
            "climate"  // single instance; the summary payload doesn't affect identity
        case .stations:
            "stations"  // the chips switch stations inside one sheet
        case .alerts:
            "alerts"
        case .settings:
            "settings"
        case .layout:
            "layout"
        }
    }
}
