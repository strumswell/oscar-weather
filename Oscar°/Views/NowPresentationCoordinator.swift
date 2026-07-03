import Foundation
import Observation

@MainActor
@Observable
final class NowPresentationCoordinator {
    var sheet: NowSheet?
    /// Testing hook: launch with `-autoPresentMap YES` (simulator/UI verification) to
    /// open the fullscreen weather map immediately instead of tapping through NowView.
    /// `-autoPresentMapLibre YES` is kept as an alias (older test harness invocations).
    var isMapPresented = UserDefaults.standard.bool(forKey: "autoPresentMap")
        || UserDefaults.standard.bool(forKey: "autoPresentMapLibre")

    func present(_ sheet: NowSheet) {
        self.sheet = sheet
    }
}
