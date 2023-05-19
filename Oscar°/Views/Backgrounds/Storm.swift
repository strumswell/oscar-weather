//
//  Storm.swift
//  Weather
//
//  Created by Paul Hudson on 03/02/2022.
//

import SwiftUI

class Storm {
    enum Contents: CaseIterable {
        case none, rain, snow
    }

    var drops = [StormDrop]()
    var lastUpdate = Date.now
    var image: Image

    init(type: Contents, direction: Angle, strength: Int) {
        switch type {
        case .snow:
            image = Image("snowParticle")
        default:
            image = Image("rainParticle")
        }

        for _ in 0..<strength {
            drops.append(StormDrop(type: type, direction: direction + .degrees(90)))
        }
    }

    func update(date: Date, size: CGSize) {
        var delta = date.timeIntervalSince1970 - lastUpdate.timeIntervalSince1970
        let divisor = size.height / size.width
        
        if delta > 10 {
            delta = 0
        }

        for drop in drops {
            let radians = drop.direction.radians

            drop.x += cos(radians) * drop.speed * delta * divisor
            drop.y += sin(radians) * drop.speed * delta

            if drop.x < -0.2 {
                drop.x += 1.4
            }

            if drop.y > 1.2 {
                drop.x = Double.random(in: -0.2...1.2)
                drop.y -= 1.4
            }
        }

        lastUpdate = date
    }
}
