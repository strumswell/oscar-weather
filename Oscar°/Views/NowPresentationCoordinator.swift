import Observation

@MainActor
@Observable
final class NowPresentationCoordinator {
    var sheet: NowSheet?
    var isMapPresented = false

    func present(_ sheet: NowSheet) {
        self.sheet = sheet
    }
}
