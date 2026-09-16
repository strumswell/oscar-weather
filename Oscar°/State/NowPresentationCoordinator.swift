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
    /// Testing hook (screenshot flows without tapping through the UI):
    /// `-autoPresentMap YES` starts on the map tab.
    var selectedTab: AppTab = UserDefaults.standard.bool(forKey: "autoPresentMap") ? .maps : .forecast

    /// Bumped when the Orte tab is tapped while already selected —
    /// LocationsView observes it and presents the search field.
    var placesSearchRequests = 0

    func present(_ sheet: NowSheet) {
        self.sheet = sheet
    }
}
