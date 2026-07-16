import Foundation

enum NowSheet: Identifiable {
    case hourly
    case daily
    case environment(EnvironmentDetailSection)
    case climate(ClimateSummary)
    case alerts

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
        }
    }
}
