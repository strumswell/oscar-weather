//
//  RadarRegion.swift
//  Oscar°
//
//  Radar coverages the user can choose between (DWD / OPERA / NOAA MRMS) and
//  the geographic bounds an overlay spans.
//

import Foundation

struct OscarRadarBounds: Equatable {
    let north: Double
    let south: Double
    let west: Double
    let east: Double
}

/// Radar coverage the user can choose between in the map's layer menu.
/// Mirrors oscar-server's radar sources: high-res DWD (Germany), the pan-European
/// EUMETNET OPERA composite, and the NOAA MRMS CONUS composite (USA).
enum RadarRegion: String, CaseIterable, Equatable, Sendable {
    case germany
    case europe
    case usa

    /// Path component used in oscar-server radar URLs (`/radar/{pathComponent}/…`).
    var pathComponent: String { rawValue }

    /// Approximate data coverage, fixed client-side so the location-based source
    /// pick works before any metadata fetch. germany/usa mirror the server
    /// composites' data bounds; europe is the OPERA LAEA bounds shrunk to the part
    /// that actually has radars (the raw box reaches Greenland and central Asia).
    private var coverage: (north: Double, south: Double, west: Double, east: Double) {
        switch self {
        case .germany: return (north: 55.86, south: 45.68, west: 1.46, east: 18.73)
        case .europe:  return (north: 71.0, south: 34.5, west: -25.0, east: 45.0)
        case .usa:     return (north: 54.99, south: 20.01, west: -129.99, east: -60.01)
        }
    }

    func covers(latitude: Double, longitude: Double) -> Bool {
        let box = coverage
        return latitude <= box.north && latitude >= box.south
            && longitude >= box.west && longitude <= box.east
    }

    /// Best radar source for a location, in fixed priority order:
    /// DWD (highest cadence/quality) → OPERA → NOAA MRMS.
    static func bestSource(latitude: Double, longitude: Double) -> RadarRegion? {
        [RadarRegion.germany, .europe, .usa].first {
            $0.covers(latitude: latitude, longitude: longitude)
        }
    }
}
