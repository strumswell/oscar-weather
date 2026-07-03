//
//  WeatherTileLayer.swift
//  Oscar°
//
//  Model tile-layer catalog (ICON-D2 / GFS × precip/temp/wind) and the
//  SettingService accessors for the active map layer selection.
//

import Foundation

// Typed accessor for SettingService — lives here so it's only compiled
// in targets that include both SettingService and WeatherTileLayer.
extension SettingService {
    var activeTileLayer: WeatherTileLayer? {
        get { activeTileLayerRaw.flatMap { WeatherTileLayer(rawValue: $0) } }
        set { activeTileLayerRaw = newValue?.rawValue }
    }

    /// Which oscar-server radar coverage the user selected for the map. Backed by
    /// `oscarRadarRegionRaw`; defaults to Germany (DWD).
    var oscarRadarRegion: RadarRegion {
        get { RadarRegion(rawValue: oscarRadarRegionRaw) ?? .germany }
        set { oscarRadarRegionRaw = newValue.rawValue }
    }

    /// True while the GFS precip layer is showing as the automatic "no radar here"
    /// fallback of `autoSelectRadarSource` — lets a later location change return
    /// to a real radar without ever overriding an explicit layer choice.
    var radarAutoFallbackActive: Bool {
        get { UserDefaults.standard.bool(forKey: "radarAutoFallbackActive") }
        set { UserDefaults.standard.set(newValue, forKey: "radarAutoFallbackActive") }
    }

    /// Location-based radar source pick: DWD → OPERA → NOAA MRMS by coverage,
    /// else the GFS precipitation forecast as the general fallback. Runs only
    /// while a radar layer is active (or while the fallback IT chose is still
    /// showing) — an explicit model/RainViewer selection is never overridden.
    func autoSelectRadarSource(latitude: Double, longitude: Double) {
        let radarIntent = oscarRadarLayer
            || (activeTileLayer == .gfsPrecip && radarAutoFallbackActive)
        guard radarIntent else { return }

        if let region = RadarRegion.bestSource(latitude: latitude, longitude: longitude) {
            radarAutoFallbackActive = false
            guard !oscarRadarLayer || oscarRadarRegion != region else { return }
            activeTileLayer = nil
            oscarRadarRegion = region
            oscarRadarLayer = true
        } else if oscarRadarLayer {
            oscarRadarLayer = false
            activeTileLayer = .gfsPrecip
            radarAutoFallbackActive = true
        }
    }
}

// MARK: WeatherTileLayer

enum WeatherTileLayer: String, CaseIterable, Hashable {
    case iconPrecip = "icon_precip"
    case iconTemp   = "icon_temp"
    case iconWind   = "icon_wind"
    case gfsPrecip  = "gfs_precip"
    case gfsTemp    = "gfs_temp"
    case gfsWind    = "gfs_wind"

    var framesEndpoint: String {
        switch self {
        case .iconPrecip, .iconTemp, .iconWind: return "models/icon/frames"
        case .gfsPrecip, .gfsTemp, .gfsWind:   return "models/gfs/frames"
        }
    }

    var tilePath: String {
        switch self {
        case .iconPrecip: return "icon/precip-tiles"
        case .iconTemp:   return "icon/temp-tiles"
        case .iconWind:   return "icon/wind-tiles"
        case .gfsPrecip:  return "gfs/prate-tiles"
        case .gfsTemp:    return "gfs/temp-tiles"
        case .gfsWind:    return "gfs/wind-tiles"
        }
    }

    /// Frames-path prefix for full-world image requests. Combined with the frame
    /// key and variable: `{imagePath}/{frameKey}/{variableSegment}/image`.
    var imagePath: String? { framesEndpoint }

    /// Variable path segment in oscar-server model URLs.
    var variableSegment: String {
        switch self {
        case .iconPrecip, .gfsPrecip: return "precipitation"
        case .iconTemp, .gfsTemp:     return "temperature"
        case .iconWind, .gfsWind:     return "wind"
        }
    }

    var sourceLabel: String {
        switch self {
        case .iconPrecip, .iconTemp, .iconWind: return "DWD ICON-D2"
        case .gfsPrecip, .gfsTemp, .gfsWind:   return "NOAA GFS"
        }
    }

    /// Server palette id (`/colormaps/{id}`) the value grids of this layer index into.
    var colormapId: String {
        switch self {
        case .iconPrecip, .gfsPrecip: return "plasma"
        case .iconTemp, .gfsTemp:     return "temperature"
        case .iconWind, .gfsWind:     return "wind_speed"
        }
    }
}
