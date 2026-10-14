//
//  StarField.swift
//  Oscar°
//
//  Created by Paul Hudson on 09/01/2022.
//

import Foundation

class StarField {
    private static let starsPerPoint = 200.0 / 550

    var stars = [Star]()
    let leftEdge = -50.0
    private(set) var rightEdge = 500.0
    var lastUpdate = Date.now

    init() {
        addStars(from: leftEdge, to: rightEdge)
    }

    func update(date: Date, width: Double) {
        if width > rightEdge {
            addStars(from: rightEdge, to: width)
            rightEdge = width
        }

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

    private func addStars(from start: Double, to end: Double) {
        for _ in 0..<Int((end - start) * Self.starsPerPoint) {
            let x = Double.random(in: start...end)
            let y = Double.random(in: 0...600)
            let size = Double.random(in: 1...3)
            stars.append(Star(x: x, y: y, size: size))
        }
    }
}
