import Foundation
import Observation

enum AppTab: Hashable {
    case forecast
    case maps
    case search
}

@MainActor
@Observable
final class NowPresentationCoordinator {
    var sheet: NowSheet?
    /// Testing hook: launch with `-autoPresentMap YES` (simulator/UI verification) to
    /// start on the fullscreen map tab instead of tapping through the UI.
    /// `-autoPresentMapLibre YES` is kept as an alias (older test harness invocations).
    var selectedTab: AppTab =
        UserDefaults.standard.bool(forKey: "autoPresentMap")
            || UserDefaults.standard.bool(forKey: "autoPresentMapLibre")
        ? .maps : .forecast

    func present(_ sheet: NowSheet) {
        self.sheet = sheet
    }
}
