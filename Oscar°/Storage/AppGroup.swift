import Foundation

enum AppGroup {
    static let identifier = "group.cloud.bolte.Oscar"
    /// `UserDefaults` is thread-safe but not annotated `Sendable` in the SDK.
    nonisolated(unsafe) static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard
}
