//
//  RadarSharedDTOs.swift
//  Oscar°
//
//  Wire DTOs for oscar-server's frames endpoints, shared by the app's timeline
//  states and the widget's snapshot renderer (compiled into both targets).
//  Frame-date parsing lives next door in RadarFrameSupport.parseFrameDate.
//

import Foundation

/// The `bounds` / `image_bounds` object on the frames endpoints.
struct RadarBoundsDTO: Decodable {
    let north: Double
    let south: Double
    let west: Double
    let east: Double

    var asDomain: OscarRadarBounds {
        OscarRadarBounds(north: north, south: south, west: west, east: east)
    }
}

/// One radar frame: server key + ISO8601 `timestamp`.
struct RadarFrameInfo: Decodable {
    let key: String
    let timestamp: String
}

/// One model frame: server key + ISO8601 `validTime` (camelCase on the wire,
/// unlike the radar endpoints' `timestamp`).
struct ModelFrameInfo: Decodable {
    let key: String
    let validTime: String
}

/// `/radar/{region}[/precip-type]/frames`. The image is rendered in Web
/// Mercator; `image_bounds` is the lat/lon of that Mercator rectangle and is
/// what an overlay must span. `bounds` is the tighter data footprint and would
/// misproject the image — most visibly for the large OPERA (Europe) extent.
struct RadarFramesResponse: Decodable {
    let frames: [RadarFrameInfo]
    let bounds: RadarBoundsDTO
    let imageBounds: RadarBoundsDTO?

    enum CodingKeys: String, CodingKey {
        case frames
        case bounds
        case imageBounds = "image_bounds"
    }
}

/// `/models/{model}/frames`. Bounds decode tolerantly (`try?`) — a missing or
/// malformed bounds object must not fail the frame list; the layers fall back
/// to the full-world rectangle.
struct ModelFramesResponse: Decodable {
    let frames: [ModelFrameInfo]
    let bounds: RadarBoundsDTO?
    let imageBounds: RadarBoundsDTO?

    enum CodingKeys: String, CodingKey {
        case frames
        case bounds
        case imageBounds = "image_bounds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frames = try container.decode([ModelFrameInfo].self, forKey: .frames)
        bounds = try? container.decode(RadarBoundsDTO.self, forKey: .bounds)
        imageBounds = try? container.decode(RadarBoundsDTO.self, forKey: .imageBounds)
    }
}
