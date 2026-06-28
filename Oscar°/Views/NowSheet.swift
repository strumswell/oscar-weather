import Foundation

enum NowSheet: Identifiable {
    case location
    case hourly
    case daily
    case environment(EnvironmentDetailSection)
    case climate(ClimateSummary)
    case alerts
    case legal

    static let locationTransitionID = "locationName"

    var id: String {
        switch self {
        case .location:
            "location"
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
        case .legal:
            "legal"
        }
    }
}
