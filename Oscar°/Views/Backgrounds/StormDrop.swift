//
//  StormDrop.swift
//  Weather
//
//  Created by Paul Hudson on 03/02/2022.
//

import SwiftUI

class StormDrop {
    var x: Double
    var y: Double
    var xScale: Double
    var yScale: Double
    var speed: Double
    var opacity: Double

    var direction: Angle
    var rotation: Angle
    var rotationSpeed: Angle

    init(type: Storm.Contents, direction: Angle) {
        if type == .snow {
            self.direction = direction + .degrees(.random(in: -15...15))
        } else {
            self.direction = direction
        }

        x = Double.random(in: -0.2...1.2)
        y = Double.random(in: -0.2...1.2)

        switch type {
        case .snow:
            xScale = Double.random(in: 0.125...1)
            yScale = xScale * Double.random(in: 0.5...1)
            speed = Double.random(in: 0.2...0.6)
            opacity = Double.random(in: 0.2...1)
            rotation = Angle.degrees(Double.random(in: 0...360))
            rotationSpeed = Angle.degrees(Double.random(in: -360...360))
        default:
            xScale = Double.random(in: 0.4...1)
            yScale = xScale
            speed = Double.random(in: 1...2)
            opacity = Double.random(in: 0.05...0.3)
            rotation = Angle.zero
            rotationSpeed = Angle.zero
        }
    }
}
