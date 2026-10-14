import Foundation

extension SettingService {
    var activeTileLayer: WeatherTileLayer? {
        get {
            guard let raw = activeTileLayerRaw else { return nil }
            if let layer = WeatherTileLayer(rawValue: raw) { return layer }
            if raw.hasPrefix("gfs_") {
                return WeatherTileLayer(rawValue: raw.replacingOccurrences(of: "gfs_", with: "ecmwf_"))
            }
            return nil
        }
        set { activeTileLayerRaw = newValue?.rawValue }
    }

    var oscarRadarRegion: RadarRegion {
        get { RadarRegion(rawValue: oscarRadarRegionRaw) ?? .germany }
        set { oscarRadarRegionRaw = newValue.rawValue }
    }

    var radarAutoFallbackActive: Bool {
        get { UserDefaults.standard.bool(forKey: "radarAutoFallbackActive") }
        set { UserDefaults.standard.set(newValue, forKey: "radarAutoFallbackActive") }
    }

    func autoSelectRadarSource(latitude: Double, longitude: Double) {
        let radarIntent = oscarRadarLayer
            || (activeTileLayer == .ecmwfPrecip && radarAutoFallbackActive)
        guard radarIntent else { return }

        if let region = RadarRegion.bestSource(latitude: latitude, longitude: longitude) {
            radarAutoFallbackActive = false
            guard !oscarRadarLayer || oscarRadarRegion != region else { return }
            activeTileLayer = nil
            oscarRadarRegion = region
            oscarRadarLayer = true
        } else if oscarRadarLayer {
            oscarRadarLayer = false
            activeTileLayer = .ecmwfPrecip
            radarAutoFallbackActive = true
        }
    }
}
