import SwiftUI

@MainActor
@Observable
final class ClimateModel {
    enum Phase {
        case idle
        case loading
        case throttled
        case loaded
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var summary: ClimateSummary?
    private var loadedKey: String?
    private var loadedCoordsKey: String?
    private var inFlightKey: String?
    private var loadGeneration = 0

    func load(latitude: Double, longitude: Double, todayHigh: Double?, identity: String) async {
        guard latitude != 0 || longitude != 0 else { return }

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
            guard generation == loadGeneration else { return }
            if let result {
                summary = result
                loadedKey = identity
                phase = .loaded
            } else {
                phase = summary == nil ? .failed : .loaded
            }
        } catch is CancellationError {
        } catch {
            guard generation == loadGeneration else { return }
            phase = summary == nil ? .failed : .loaded
        }
    }
}
