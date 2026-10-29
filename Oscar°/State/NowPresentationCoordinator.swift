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
    var sheet: NowSheet? = UserDefaults.standard.bool(forKey: "autoPresentSettings") ? .settings : nil {
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
            if selectedTab != .maps { isLayerPickerPresented = false }
            UsageStatsStore.shared.record { $0.tabs["\(selectedTab)", default: 0] += 1 }
        }
    }

    /// Bumped when the Orte tab is tapped while already selected —
    /// LocationsView observes it and presents the search field.
    var placesSearchRequests = 0

    /// The diver sits behind the full-size tab bar, so the bar stays full while a cat is out.
    var isNudgeOut = false
    var requestedNudge: SupportNudge.Pose?

    var isLayerPickerPresented = false
    /// Latched by NowView.
    var forecastSize: CGSize?
    var forecastIsWide: Bool { (forecastSize?.width ?? 0) >= WideForecast.minWidth }
    /// Set by the map when it opens the picker: radar region, model layer, or neither (clouds).
    var selectLayer: (RadarRegion?, WeatherTileLayer?) -> Void = { _, _ in }

    func present(_ sheet: NowSheet) {
        self.sheet = sheet
    }
}
