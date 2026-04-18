import Foundation

// MARK: - Response models

struct WindFieldBounds: Decodable, Sendable {
    let north: Double
    let south: Double
    let west: Double
    let east: Double

    func contains(latitude: Double, longitude: Double) -> Bool {
        latitude >= south && latitude <= north &&
        longitude >= west && longitude <= east
    }
}

struct WindFieldTile: Decodable, Sendable {
    let gridWidth: Int
    let gridHeight: Int
    let bounds: WindFieldBounds
    let u: [Double?]
    let v: [Double?]
}

struct WindTileKey: Hashable, Sendable {
    let frameId: String
    let z: Int
    let x: Int
    let y: Int
}

// MARK: - WeatherTileLayer helpers for wind-field

extension WeatherTileLayer {
    var windFieldPrefix: String {
        switch self {
        case .gfsPrecip, .gfsTemp, .gfsWind: "gfs"
        case .iconPrecip, .iconTemp, .iconWind: "icon"
        }
    }

    var windFieldSamples: Int { self == .gfsWind ? 24 : 32 }
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
            let key = WindTileKey(frameId: frameId, z: z, x: x, y: y)
            guard tiles[key] == nil, fetching[key] == nil else { continue }
            fetching[key] = makeTask(key: key, layer: layer)
        }
    }

    /// Drop tiles for frame IDs outside the retention set.
    func evict(retaining keepIds: Set<String>) {
        tiles = tiles.filter { keepIds.contains($0.key.frameId) }
        for key in Array(fetching.keys) where !keepIds.contains(key.frameId) {
            fetching[key]?.cancel()
            fetching.removeValue(forKey: key)
        }
    }

    // MARK: - Private

    private func makeTask(key: WindTileKey, layer: WeatherTileLayer) -> Task<WindFieldTile?, Never> {
        let task = Task<WindFieldTile?, Never> {
            let result = await Self.fetch(key: key, layer: layer)
            // Re-acquire actor after suspension to update cache state.
            self.fetching.removeValue(forKey: key)
            if let result { self.tiles[key] = result }
            return result
        }
        fetching[key] = task
        return task
    }

    private static func fetch(key: WindTileKey, layer: WeatherTileLayer) async -> WindFieldTile? {
        let urlString =
            "\(GFSImageLayerState.baseURL)/\(layer.windFieldPrefix)/wind-field"
            + "/\(key.frameId)/\(key.z)/\(key.x)/\(key.y).json?samples=\(layer.windFieldSamples)"
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.addAPIContactIdentity()
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(WindFieldTile.self, from: data)
    }
}
