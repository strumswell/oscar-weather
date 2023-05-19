//
//  StarField.swift
//  Weather
//
//  Created by Paul Hudson on 09/01/2022.
//

import Foundation

class StarField {
    var stars = [Star]()
    let leftEdge = -50.0
    let rightEdge = 500.0
    var lastUpdate = Date.now

    init() {
        for _ in 1...200 {
            let x = Double.random(in: leftEdge...rightEdge)
            let y = Double.random(in: 0...600)
            let size = Double.random(in: 1...3)
            let star = Star(x: x, y: y, size: size)
            stars.append(star)
        }
    }

    func update(date: Date) {
        var delta = date.timeIntervalSince1970 - lastUpdate.timeIntervalSince1970

        if delta > 10 {
            delta = 0
        }

        for star in stars {
            star.x -= delta * 2

            if star.x < leftEdge {
                star.x = rightEdge
            }
            if star.x > rightEdge {
                star.x = rightEdge
            }
        }

        lastUpdate = date
    }
}
