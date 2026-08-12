import Foundation

enum NowSheet: Identifiable {
    case hourly
    case daily
    case environment(EnvironmentDetailSection)
    case climate(ClimateSummary)
    case alerts
    case meteorShower(MeteorShowerEvent)
    case settings

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
        case .alerts:
            "alerts"
        case .meteorShower(let event):
            "meteor-shower-\(event.id)"
        case .settings:
            "settings"
        }
    }
}
