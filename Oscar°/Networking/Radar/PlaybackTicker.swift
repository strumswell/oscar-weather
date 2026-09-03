import Foundation

/// Repeating main-actor tick for timeline playback; ends on `stop()` or deinit.
@MainActor
final class PlaybackTicker {
    private var task: Task<Void, Never>?

    func start(interval: Duration, _ tick: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                tick()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
