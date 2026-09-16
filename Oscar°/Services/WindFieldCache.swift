import Foundation

// MARK: - Response models

typealias WindFieldTile = Components.Schemas.WindFieldTile

extension Components.Schemas.RadarBounds {
    func contains(latitude: Double, longitude: Double) -> Bool {
        latitude >= south && latitude <= north &&
        longitude >= west && longitude <= east
    }
}

struct WindTileKey: Hashable, Sendable {
    let model: String
    let frameId: String
    let z: Int
    let x: Int
    let y: Int
}

// MARK: - Cache

actor WindFieldCache {
    static let shared = WindFieldCache()

    private var tiles: [WindTileKey: WindFieldTile] = [:]
    private var fetching: [WindTileKey: Task<WindFieldTile?, Never>] = [:]

    private init() {}

    // MARK: - Public API

    /// Returns a cached tile immediately, or fetches it (deduplicating concurrent requests).
    func tile(key: WindTileKey, layer: WeatherTileLayer) async -> WindFieldTile? {
        if let hit = tiles[key] { return hit }
        let task = fetching[key] ?? makeTask(key: key, layer: layer)
        return await task.value
    }

    /// Fire-and-forget prefetch for a set of tile positions.
    func prefetch(frameId: String, z: Int, positions: [(x: Int, y: Int)], layer: WeatherTileLayer) {
        for (x, y) in positions {
            let key = WindTileKey(
                model: layer.windFieldPrefix, frameId: frameId, z: z, x: x, y: y)
            guard tiles[key] == nil, fetching[key] == nil else { continue }
            fetching[key] = makeTask(key: key, layer: layer)
        }
    }

    /// Drop tiles for frame IDs outside the retention set.
    func evict(retaining keepIds: Set<String>, model: String? = nil) {
        tiles = tiles.filter { key, _ in
            (model != nil && key.model != model) || keepIds.contains(key.frameId)
        }
        for key in Array(fetching.keys)
        where (model != nil && key.model != model) || !keepIds.contains(key.frameId) {
            fetching[key]?.cancel()
            fetching.removeValue(forKey: key)
        }
    }

    // MARK: - Private

    private func makeTask(key: WindTileKey, layer: WeatherTileLayer) -> Task<WindFieldTile?, Never> {
        let task = Task<WindFieldTile?, Never> {
            let result = await Self.fetch(key: key, layer: layer)
            guard !Task.isCancelled else { return result }
            self.fetching.removeValue(forKey: key)
            if let result { self.tiles[key] = result }
            return result
        }
        fetching[key] = task
        return task
    }

    private static func fetch(key: WindTileKey, layer: WeatherTileLayer) async -> WindFieldTile? {
        try? await APIClient.shared.windField(
            model: key.model, key: key.frameId, z: key.z, x: key.x, y: key.y, samples: layer.windFieldSamples)
    }
}
