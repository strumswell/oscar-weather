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
    var sheet: NowSheet? {
        didSet {
            guard let sheet else { return }
            UsageStatsStore.shared.record { $0.sheets[sheet.id, default: 0] += 1 }
        }
    }
    /// Testing hook (screenshot flows without tapping through the UI):
    /// `-autoPresentMap YES` starts on the map tab.
    var selectedTab: AppTab = UserDefaults.standard.bool(forKey: "autoPresentMap") ? .maps : .forecast {
        didSet {
            guard selectedTab != oldValue else { return }
            UsageStatsStore.shared.record { $0.tabs["\(selectedTab)", default: 0] += 1 }
        }
    }

    /// Bumped when the Orte tab is tapped while already selected —
    /// LocationsView observes it and presents the search field.
    var placesSearchRequests = 0

    func present(_ sheet: NowSheet) {
        self.sheet = sheet
    }
}
