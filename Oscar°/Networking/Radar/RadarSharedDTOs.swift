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

extension Components.Schemas.RadarBounds {
    var asDomain: OscarRadarBounds { OscarRadarBounds(north: north, south: south, west: west, east: east) }
}

extension Components.Schemas.ModelBounds {
    var asDomain: OscarRadarBounds? {
        guard let north, let south, let west, let east else { return nil }
        return OscarRadarBounds(north: north, south: south, west: west, east: east)
    }
}
