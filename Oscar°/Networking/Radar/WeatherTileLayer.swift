//
//  WeatherTileLayer.swift
//  Oscar°
//
//  Model layer catalog (ICON-D2 / ECMWF × precip/temp/wind/pressure) and the
//  SettingService accessors for the active map layer selection.
//

import Foundation

// Typed accessor for SettingService — lives here so it's only compiled
// in targets that include both SettingService and WeatherTileLayer.
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

    /// The radar product the map shows, resolved from the "Niederschlagsart" toggle
    /// and the active region's coverage (OPERA has no type product → plain radar).
    var oscarRadarProduct: RadarProduct {
        radarPrecipTypeOverlay && RadarProduct.precipitationTyped.isAvailable(in: oscarRadarRegion)
            ? .precipitationTyped
            : .precipitation
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
            // The typed product's regional availability is resolved inside
            // `oscarRadarProduct`, so a region switch needs no product fix-up.
            oscarRadarRegion = region
            oscarRadarLayer = true
        } else if oscarRadarLayer {
            oscarRadarLayer = false
            activeTileLayer = .ecmwfPrecip
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
    case ecmwfPrecip = "ecmwf_precip"
    case ecmwfTemp = "ecmwf_temp"
    case ecmwfWind = "ecmwf_wind"
    case ecmwfPressure = "ecmwf_pressure"

    var framesEndpoint: String {
        switch self {
        case .iconPrecip, .iconTemp, .iconWind, .iconPressure: return "models/icon/frames"
        case .ecmwfPrecip, .ecmwfTemp, .ecmwfWind, .ecmwfPressure: return "models/ecmwf/frames"
        }
    }

    /// Frames-path prefix for grid requests. Combined with the frame key and
    /// variable: `{imagePath}/{frameKey}/{variableSegment}/grid`.
    var imagePath: String? { framesEndpoint }

    /// Variable path segment in oscar-server model URLs.
    var variableSegment: String {
        switch self {
        case .iconPrecip, .ecmwfPrecip:       return "precipitation"
        case .iconTemp, .ecmwfTemp:            return "temperature"
        case .iconWind, .ecmwfWind:            return "wind"
        case .iconPressure, .ecmwfPressure:    return "pressure"
        }
    }

    var isPressureLayer: Bool {
        switch self {
        case .iconPressure, .ecmwfPressure:
            true
        default:
            false
        }
    }

    var sourceLabel: String {
        switch self {
        case .iconPrecip, .iconTemp, .iconWind, .iconPressure: return "DWD ICON-D2"
        case .ecmwfPrecip, .ecmwfTemp, .ecmwfWind, .ecmwfPressure: return "ECMWF IFS"
        }
    }

    /// Server palette id (`/colormaps/{id}`) the value grids of this layer index into.
    var colormapId: String {
        switch self {
        case .iconPrecip, .ecmwfPrecip:     return "plasma"
        case .iconTemp, .ecmwfTemp:          return "temperature"
        case .iconWind, .ecmwfWind:          return "wind_speed"
        case .iconPressure, .ecmwfPressure:  return "pressure"
        }
    }

    var isGlobalModel: Bool {
        switch self {
        case .ecmwfPrecip, .ecmwfTemp, .ecmwfWind, .ecmwfPressure:
            true
        default:
            false
        }
    }
}

extension WeatherTileLayer {
    /// oscar-server model id path segment ("models/{id}/…") for this layer.
    var windFieldPrefix: String {
        switch self {
        case .iconPrecip, .iconTemp, .iconWind, .iconPressure: "icon"
        case .ecmwfPrecip, .ecmwfTemp, .ecmwfWind, .ecmwfPressure: "ecmwf"
        }
    }

    var windFieldSamples: Int { isGlobalModel ? 24 : 32 }
}
