//
//  RadarSharedDTOs.swift
//  Oscar°
//
//  Generated wire types (OpenAPI client) for oscar-server's frames endpoints,
//  shared by the app's timeline states and the widget's snapshot renderer
//  (compiled into both targets). Frame-date parsing lives next door in
//  RadarFrameSupport.parseFrameDate.
//

import Foundation

typealias RadarFramesResponse = Components.Schemas.RadarFramesResponse
typealias ModelFramesResponse = Components.Schemas.ModelFramesResponse
typealias RadarFrameInfo = Components.Schemas.RadarFrameInfo
typealias ModelFrameInfo = Components.Schemas.ModelFrameInfo

/// The `bounds` / `image_bounds` object on the frames endpoints (generated as
/// `image_bounds`, not `imageBounds` — the wire spelling, unlike `validTime` on
/// `ModelFrameInfo`, isn't camelCased by the generator).
extension Components.Schemas.RadarBounds {
    var asDomain: OscarRadarBounds { OscarRadarBounds(north: north, south: south, west: west, east: east) }
}

/// Model frames `bounds` is shape-polymorphic: ECMWF serves lat/lon edges, ICON
/// a Mercator {minX,…} rectangle (its lat/lon rectangle is `image_bounds`), so
/// the schema keeps every field optional and the mapping yields nil unless all
/// four edges are present — callers fall through to `image_bounds` first anyway.
extension Components.Schemas.ModelBounds {
    var asDomain: OscarRadarBounds? {
        guard let north, let south, let west, let east else { return nil }
        return OscarRadarBounds(north: north, south: south, west: west, east: east)
    }
}
