import Foundation

/// 256-entry RGBA palettes from `/colormaps/{id}`, resolved once per process, with
/// local fallbacks for the ids the app can build itself.
@MainActor
enum ServerPalettes {
    private static var cache: [String: [PixelRGBA]] = [:]
    private static var inFlight: [String: Task<[PixelRGBA]?, Never>] = [:]
    private static var failedAt: [String: Date] = [:]
    private static let retryInterval: TimeInterval = 60

    /// Server palette, else the local fallback for known ids, else nil. Concurrent
    /// callers share one request, and a failed id is not retried for a minute.
    static func resolve(id: String) async -> [PixelRGBA]? {
        if let cached = cache[id] { return cached }
        if let running = inFlight[id] { return await running.value }
        if let failed = failedAt[id], Date().timeIntervalSince(failed) < retryInterval {
            return fallback(id: id)
        }
        let task = Task { await fetch(id: id) }
        inFlight[id] = task
        let fetched = await task.value
        inFlight[id] = nil
        if let fetched {
            cache[id] = fetched
            failedAt[id] = nil
            return fetched
        }
        failedAt[id] = Date()
        return fallback(id: id)
    }

    private static func fetch(id: String) async -> [PixelRGBA]? {
        guard let data = try? await APIClient.shared.colormap(id: id), data.count == 256 * 4 else { return nil }
        return (0..<256).map {
            let o = $0 * 4
            return PixelRGBA(r: data[o], g: data[o + 1], b: data[o + 2], a: data[o + 3])
        }
    }

    private static func fallback(id: String) -> [PixelRGBA]? {
        switch id {
        case RadarPlasma.colormapId: RadarPlasma.buildPalette()
        case CloudLayerState.colormapId: CloudLayerState.localPalette
        default: nil
        }
    }
}
