//
//  RadarRegion.swift
//  Oscar°
//
//  Radar coverages the user can choose between (DWD / OPERA / NOAA MRMS / CWA)
//  and the geographic bounds an overlay spans.
//

import Foundation

struct OscarRadarBounds: Equatable {
    let north: Double
    let south: Double
    let west: Double
    let east: Double
}

/// Radar product family served by oscar-server: the plain precipitation radar or
/// the typed variant — the same frames with the "Niederschlagsart" overlay baked in
/// (intensity+type combined grid, DWD HG / MRMS PrecipFlag; see server `TypedRadar`).
enum RadarProduct: String, CaseIterable, Equatable, Sendable {
    case precipitation
    case precipitationTyped = "precipitation_typed"

    /// Frames endpoint path (`{framesPath}/…` also prefixes the grid URLs).
    /// Both products share ONE timeline — typed only changes the grid encoding.
    func framesPath(for region: RadarRegion) -> String {
        "radar/\(region.pathComponent)/frames"
    }

    /// Query string appended to grid asset URLs (`grid?style=typed`).
    var gridQuery: String {
        self == .precipitationTyped ? "?style=typed" : ""
    }

    /// Server palette id (`/colormaps/{id}`) the value grids of this product index into.
    var colormapId: String {
        switch self {
        case .precipitation:      return "plasma"
        case .precipitationTyped: return "radar_typed"
        }
    }

    /// The typed product exists only for the DWD and MRMS composites — neither
    /// OPERA nor CWA publishes a hydrometeor-classification product.
    func isAvailable(in region: RadarRegion) -> Bool {
        self == .precipitation || region == .germany || region == .usa
    }
}

/// Radar coverage the user can choose between in the map's layer menu.
/// Mirrors oscar-server's radar sources: high-res DWD (Germany), the pan-European
/// EUMETNET OPERA composite, the NOAA MRMS CONUS composite (USA), and the CWA
/// QPESUMS composite (Taiwan).
enum RadarRegion: String, CaseIterable, Equatable, Sendable {
    case germany
    case europe
    case usa
    case taiwan

    /// Path component used in oscar-server radar URLs (`/radar/{pathComponent}/…`).
    var pathComponent: String { rawValue }

    /// Approximate data coverage, fixed client-side so the location-based source
    /// pick works before any metadata fetch. germany/usa mirror the server
    /// composites' data bounds; europe is the OPERA LAEA bounds shrunk to the part
    /// that actually has radars (the raw box reaches Greenland and central Asia);
    /// taiwan is the 7-radar footprint, not the published rectangle (which reaches
    /// mainland China and Luzon where every pixel is a no-coverage sentinel).
    private var coverage: (north: Double, south: Double, west: Double, east: Double) {
        switch self {
        case .germany: return (north: 55.86, south: 45.68, west: 1.46, east: 18.73)
        case .europe:  return (north: 71.0, south: 34.5, west: -25.0, east: 45.0)
        case .usa:     return (north: 54.99, south: 20.01, west: -129.99, east: -60.01)
        case .taiwan:  return (north: 26.5, south: 20.5, west: 118.0, east: 124.0)
        }
    }

    func covers(latitude: Double, longitude: Double) -> Bool {
        let box = coverage
        return latitude <= box.north && latitude >= box.south
            && longitude >= box.west && longitude <= box.east
    }

    /// Best radar source for a location, in fixed priority order:
    /// DWD (highest cadence/quality) → OPERA → NOAA MRMS → CWA.
    static func bestSource(latitude: Double, longitude: Double) -> RadarRegion? {
        [RadarRegion.germany, .europe, .usa, .taiwan].first {
            $0.covers(latitude: latitude, longitude: longitude)
        }
    }
}
