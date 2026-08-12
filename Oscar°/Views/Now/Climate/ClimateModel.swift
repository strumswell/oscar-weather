import SwiftUI

@MainActor
@Observable
final class ClimateModel {
    enum Phase {
        case idle
        case loading
        /// Blocked on the archive rate limiter (cold fetch over the per-minute budget).
        case throttled
        case loaded
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var summary: ClimateSummary?
    /// Identity (coords | day | high) of the summary currently shown.
    private var loadedKey: String?
    /// Coordinates of the last load. The card is blanked to its placeholder only when *this*
    /// changes (a real location switch), so a same-location refresh or midnight rollover updates
    /// in place instead of flashing the placeholder.
    private var loadedCoordsKey: String?
    /// Identity currently being fetched, so a refresh-triggered reload doesn't restart an in-flight
    /// (possibly expensive cold) fetch for the same inputs.
    private var inFlightKey: String?
    /// Bumped per load so a superseded one can't overwrite newer state — both the throttle callback
    /// and the result/failure assignment check it.
    private var loadGeneration = 0

    /// `identity` encodes the inputs (coords | calendar day | today's high); the view re-runs this
    /// whenever any of them change, and also on each weather refresh (to retry a failed/stale load).
    func load(latitude: Double, longitude: Double, todayHigh: Double?, identity: String) async {
        // Skip an unresolved location (the section is hosted only once the forecast has content,
        // so this is essentially the pre-first-load instant).
        guard latitude != 0 || longitude != 0 else { return }

        // Already showing a current summary for these exact inputs, or already loading them.
        if (identity == loadedKey && summary != nil) || identity == inFlightKey { return }

        let coordsKey = String(format: "%.2f,%.2f", latitude, longitude)
        if coordsKey != loadedCoordsKey { summary = nil }
        loadedCoordsKey = coordsKey

        if summary == nil { phase = .loading }
        loadGeneration &+= 1
        let generation = loadGeneration
        inFlightKey = identity
        defer { if inFlightKey == identity { inFlightKey = nil } }

        do {
            let result = try await ClimateArchiveStore.shared.summary(
                latitude: latitude,
                longitude: longitude,
                today: .now,
                todayHigh: todayHigh
            ) { [weak self] in
                Task { @MainActor in
                    guard let self, self.loadGeneration == generation else { return }
                    if self.summary == nil { self.phase = .throttled }
                }
            }
            // A newer load (location / day / high changed) superseded this one — don't clobber it.
            guard generation == loadGeneration else { return }
            if let result {
                summary = result
                loadedKey = identity
                phase = .loaded
            } else {
                // No usable data yet. Leave loadedKey unset so a later refresh retries; hide the
                // section if there's nothing to show, else keep the last-good summary.
                phase = summary == nil ? .failed : .loaded
            }
        } catch is CancellationError {
            // Superseded by a newer load; it will drive state.
        } catch {
            guard generation == loadGeneration else { return }
            phase = summary == nil ? .failed : .loaded
        }
    }
}
