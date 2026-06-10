import Foundation

enum NowSheet: Identifiable {
    case location
    case hourly
    case daily
    case environment(EnvironmentDetailSection)
    case alerts
    case legal
    case map

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
        case .alerts:
            "alerts"
        case .legal:
            "legal"
        case .map:
            "map"
        }
    }
}
