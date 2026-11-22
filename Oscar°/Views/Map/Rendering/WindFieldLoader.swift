import Foundation
import MapLibre

@MainActor
final class WindFieldLoader {
    weak var mapView: MLNMapView?

    weak var layer: WindParticleLayer? {
        didSet { layer?.setField(WindField(tiles: tiles)) }
    }

    var frameKey: String? {
        didSet {
            guard frameKey != oldValue else { return }
            reload()
        }
    }

    var activeLayer: WeatherTileLayer? {
        didSet {
            guard activeLayer != oldValue else { return }
            tiles = []
            reload()
        }
    }

    private var tiles: [WindFieldTile] = [] {
        didSet { layer?.setField(WindField(tiles: tiles)) }
    }

    private var fetchVisibleTilesTask: Task<Void, Never>?

    func onMapRegionChanged() {
        guard let key = frameKey, let layer = activeLayer else { return }
        fetchVisibleTiles(frameId: key, layer: layer)
    }

    func prefetchFrame(frameId: String, layer: WeatherTileLayer) {
        guard let mapView else { return }
        let (z, positions) = visibleTilePositions(in: mapView)
        Task { await WindFieldCache.shared.prefetch(frameId: frameId, z: z, positions: positions, layer: layer) }
    }

    private func reload() {
        guard let key = frameKey, let layer = activeLayer else {
            fetchVisibleTilesTask?.cancel()
            tiles = []
            return
        }
        fetchVisibleTiles(frameId: key, layer: layer)
    }

    private func fetchVisibleTiles(frameId: String, layer: WeatherTileLayer) {
        fetchVisibleTilesTask?.cancel()
        guard let mapView else { return }
        let (z, positions) = visibleTilePositions(in: mapView)

        fetchVisibleTilesTask = Task {
            var nextTiles: [WindFieldTile] = []
            await withTaskGroup(of: WindFieldTile?.self) { group in
                for (x, y) in positions {
                    let cacheKey = WindTileKey(
                        model: layer.windFieldPrefix, frameId: frameId, z: z, x: x, y: y)
                    group.addTask { await WindFieldCache.shared.tile(key: cacheKey, layer: layer) }
                }
                for await tile in group {
                    guard !Task.isCancelled, let tile else { continue }
                    nextTiles.append(tile)
                }
            }
            guard !Task.isCancelled else { return }
            tiles = nextTiles
        }
    }

    private func visibleTilePositions(in mapView: MLNMapView) -> (z: Int, positions: [(x: Int, y: Int)]) {
        let visible = mapView.visibleCoordinateBounds
        let z = approximateZoomLevel(for: mapView)
        let tilesPerSide = 1 << z

        let nw = Self.mercatorUnit(latitude: visible.ne.latitude, longitude: visible.sw.longitude)
        let se = Self.mercatorUnit(latitude: visible.sw.latitude, longitude: visible.ne.longitude)
        let minX = max(0, Int(nw.x * Double(tilesPerSide)))
        let maxX = min(tilesPerSide - 1, Int(se.x * Double(tilesPerSide)))
        let minY = max(0, Int(nw.y * Double(tilesPerSide)))
        let maxY = min(tilesPerSide - 1, Int(se.y * Double(tilesPerSide)))

        guard minX <= maxX, minY <= maxY else { return (z, []) }

        var positions: [(x: Int, y: Int)] = []
        for tx in minX...maxX {
            for ty in minY...maxY {
                positions.append((x: tx, y: ty))
            }
        }
        return (z, positions)
    }

    private func approximateZoomLevel(for mapView: MLNMapView) -> Int {
        let visible = mapView.visibleCoordinateBounds
        let lonSpan = visible.ne.longitude - visible.sw.longitude
        return max(0, min(8, Int(log2(360.0 / max(0.001, lonSpan)).rounded()) + 1))
    }

    private static func mercatorUnit(latitude: Double, longitude: Double) -> (x: Double, y: Double) {
        let lat = min(WebMercator.maxLatitude, max(-WebMercator.maxLatitude, latitude))
        return (WebMercator.unitX(longitude: longitude), WebMercator.unitY(latitude: lat))
    }
}
