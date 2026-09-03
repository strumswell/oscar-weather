import Foundation

/// Map layer selection: the active model layer, radar region and the
/// location-based radar auto-pick.
extension SettingService {
    var activeTileLayer: WeatherTileLayer? {
        get {
            guard let raw = activeTileLayerRaw else { return nil }
            if let layer = WeatherTileLayer(rawValue: raw) { return layer }
            // The GFS layers were removed (July 2026); a persisted pick
            // migrates to its ECMWF twin instead of silently clearing.
            if raw.hasPrefix("gfs_") {
                return WeatherTileLayer(rawValue: raw.replacingOccurrences(of: "gfs_", with: "ecmwf_"))
            }
            return nil
        }
        set { activeTileLayerRaw = newValue?.rawValue }
    }

    /// Which oscar-server radar coverage the user selected for the map. Backed by
    /// `oscarRadarRegionRaw`; defaults to Germany (DWD).
    var oscarRadarRegion: RadarRegion {
        get { RadarRegion(rawValue: oscarRadarRegionRaw) ?? .germany }
        set { oscarRadarRegionRaw = newValue.rawValue }
    }

    /// True while the ECMWF precip layer is showing as the automatic "no radar
    /// here" fallback of `autoSelectRadarSource` — lets a later location change
    /// return to a real radar without ever overriding an explicit layer choice.
    var radarAutoFallbackActive: Bool {
        get { UserDefaults.standard.bool(forKey: "radarAutoFallbackActive") }
        set { UserDefaults.standard.set(newValue, forKey: "radarAutoFallbackActive") }
    }

    /// Location-based radar source pick: DWD → OPERA → NOAA MRMS by coverage,
    /// else the ECMWF precipitation forecast as the general fallback. Runs only
    /// while a radar layer is active (or while the fallback IT chose is still
    /// showing) — an explicit model selection is never overridden.
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
