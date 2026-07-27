import Foundation
import Observation

enum AppTab: Hashable {
    case forecast
    case maps
    case places
}

@MainActor
@Observable
final class NowPresentationCoordinator {
    var sheet: NowSheet?
    /// Testing hooks (simulator/UI verification without tapping through the
    /// UI): `-autoPresentMap YES` starts on the map tab (`-autoPresentMapLibre
    /// YES` kept as an alias for older test harness invocations),
    /// `-autoPresentPlaces YES` on the Orte tab.
    var selectedTab: AppTab = {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "autoPresentMap") || defaults.bool(forKey: "autoPresentMapLibre") {
            return .maps
        }
        if defaults.bool(forKey: "autoPresentPlaces") {
            return .places
        }
        return .forecast
    }()

    func present(_ sheet: NowSheet) {
        self.sheet = sheet
    }
}
