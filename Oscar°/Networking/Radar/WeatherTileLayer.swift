//
//  WeatherTileLayer.swift
//  Oscar°
//
//  Model layer catalog (ICON-D2 / ECMWF × precip/temp/wind/pressure).
//

import Foundation

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
