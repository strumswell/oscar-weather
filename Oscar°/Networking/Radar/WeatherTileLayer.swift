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

    var framesEndpoint: String { isGlobalModel ? "models/ecmwf/frames" : "models/icon/frames" }

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

    var sourceLabel: String { isGlobalModel ? "ECMWF IFS" : "DWD ICON-D2" }

    var colormapId: String {
        switch self {
        case .iconPrecip, .ecmwfPrecip:     return "plasma"
        case .iconTemp, .ecmwfTemp:          return "temperature"
        case .iconWind, .ecmwfWind:          return "wind_speed"
        case .iconPressure, .ecmwfPressure:  return "pressure"
        }
    }

    var shortSourceLabel: String { isGlobalModel ? "ECMWF" : "ICON-D2" }

    var horizonHours: Int { isGlobalModel ? 84 : 36 }

    var isGlobalModel: Bool {
        switch self {
        case .ecmwfPrecip, .ecmwfTemp, .ecmwfWind, .ecmwfPressure:
            true
        case .iconPrecip, .iconTemp, .iconWind, .iconPressure:
            false
        }
    }
}

extension WeatherTileLayer {
    var windFieldPrefix: String { isGlobalModel ? "ecmwf" : "icon" }

    var windFieldSamples: Int { isGlobalModel ? 24 : 32 }
}

extension RadarRegion {
    var continuationLayer: WeatherTileLayer {
        self == .germany ? .iconPrecip : .ecmwfPrecip
    }
}
