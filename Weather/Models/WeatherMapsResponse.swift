//
//  RadarTimeResponse.swift
//  RadarTimeResponse
//
//  Created by Philipp Bolte on 11.08.21.
//

import Foundation

struct WeatherMapsResponse: Codable {
    let version: String
    let generated: Int
    let host: String
    let radar: Radar
    let satellite: Satellite
}

struct Radar: Codable {
    let past, nowcast: [Nowcast]
}

struct Nowcast: Codable {
    let time: Int
    let path: String
}

struct Satellite: Codable {
    let infrared: [Nowcast]
}
