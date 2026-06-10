import Observation

@MainActor
@Observable
final class NowPresentationCoordinator {
    var sheet: NowSheet?

    func present(_ sheet: NowSheet) {
        self.sheet = sheet
    }
}
