//
//  WeatherTileLayer.swift
//  Oscar°
//
//  Model layer catalog (ICON-D2 / GFS / ECMWF × precip/temp/wind/pressure) and the
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

    /// The radar product the map shows, resolved from the "Niederschlagsart" toggle
    /// and the active region's coverage (OPERA has no type product → plain radar).
    var oscarRadarProduct: RadarProduct {
        radarPrecipTypeOverlay && RadarProduct.precipitationTyped.isAvailable(in: oscarRadarRegion)
            ? .precipitationTyped
            : .precipitation
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
    /// showing) — an explicit model selection is never overridden.
    func autoSelectRadarSource(latitude: Double, longitude: Double) {
        let radarIntent = oscarRadarLayer
            || (activeTileLayer == .gfsPrecip && radarAutoFallbackActive)
        guard radarIntent else { return }

        if let region = RadarRegion.bestSource(latitude: latitude, longitude: longitude) {
            radarAutoFallbackActive = false
            guard !oscarRadarLayer || oscarRadarRegion != region else { return }
            activeTileLayer = nil
            // The typed product's regional availability is resolved inside
            // `oscarRadarProduct`, so a region switch needs no product fix-up.
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
    case iconPressure = "icon_pressure"
    case gfsPrecip  = "gfs_precip"
    case gfsTemp    = "gfs_temp"
    case gfsWind    = "gfs_wind"
    case gfsPressure = "gfs_pressure"
    case ecmwfPrecip = "ecmwf_precip"
    case ecmwfTemp = "ecmwf_temp"
    case ecmwfWind = "ecmwf_wind"
    case ecmwfPressure = "ecmwf_pressure"

    var framesEndpoint: String {
        switch self {
        case .iconPrecip, .iconTemp, .iconWind, .iconPressure: return "models/icon/frames"
        case .gfsPrecip, .gfsTemp, .gfsWind, .gfsPressure:     return "models/gfs/frames"
        case .ecmwfPrecip, .ecmwfTemp, .ecmwfWind, .ecmwfPressure: return "models/ecmwf/frames"
        }
    }

    /// Frames-path prefix for grid requests. Combined with the frame key and
    /// variable: `{imagePath}/{frameKey}/{variableSegment}/grid`.
    var imagePath: String? { framesEndpoint }

    /// Variable path segment in oscar-server model URLs.
    var variableSegment: String {
        switch self {
        case .iconPrecip, .gfsPrecip, .ecmwfPrecip:       return "precipitation"
        case .iconTemp, .gfsTemp, .ecmwfTemp:              return "temperature"
        case .iconWind, .gfsWind, .ecmwfWind:              return "wind"
        case .iconPressure, .gfsPressure, .ecmwfPressure:  return "pressure"
        }
    }

    var isPressureLayer: Bool {
        switch self {
        case .iconPressure, .gfsPressure, .ecmwfPressure:
            true
        default:
            false
        }
    }

    var sourceLabel: String {
        switch self {
        case .iconPrecip, .iconTemp, .iconWind, .iconPressure: return "DWD ICON-D2"
        case .gfsPrecip, .gfsTemp, .gfsWind, .gfsPressure:     return "NOAA GFS"
        case .ecmwfPrecip, .ecmwfTemp, .ecmwfWind, .ecmwfPressure: return "ECMWF IFS"
        }
    }

    /// Server palette id (`/colormaps/{id}`) the value grids of this layer index into.
    var colormapId: String {
        switch self {
        case .iconPrecip, .gfsPrecip, .ecmwfPrecip:     return "plasma"
        case .iconTemp, .gfsTemp, .ecmwfTemp:            return "temperature"
        case .iconWind, .gfsWind, .ecmwfWind:            return "wind_speed"
        case .iconPressure, .gfsPressure, .ecmwfPressure: return "pressure"
        }
    }

    var isGlobalModel: Bool {
        switch self {
        case .gfsPrecip, .gfsTemp, .gfsWind, .gfsPressure,
             .ecmwfPrecip, .ecmwfTemp, .ecmwfWind, .ecmwfPressure:
            true
        default:
            false
        }
    }
}
