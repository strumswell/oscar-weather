import Foundation

enum AppGroup {
    static let identifier = "group.cloud.bolte.Oscar"
    nonisolated(unsafe) static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard
}
