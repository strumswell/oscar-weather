//
//  Storm.swift
//  Oscar°
//
//  Created by Paul Hudson on 03/02/2022.
//

import SwiftUI

class Storm {
    enum Contents: CaseIterable {
        case none, rain, snow
    }

    private(set) lazy var drops: [StormDrop] = (0..<initialStrength).map { _ in
        StormDrop(type: self.type, direction: self.initialDirection + .degrees(90))
    }
    var lastUpdate = Date.now
    var image: Image
    private let type: Contents
    private let initialDirection: Angle
    private let initialStrength: Int

    init(type: Contents, direction: Angle, strength: Int) {
        self.type = type
        initialDirection = direction
        initialStrength = strength
        switch type {
        case .snow:
            image = Image("snowParticle")
        default:
            image = Image("rainParticle")
        }
    }

    func sync(strength: Int, direction: Angle) {
        if drops.count < strength {
            for _ in drops.count..<strength {
                drops.append(StormDrop(type: type, direction: direction + .degrees(90)))
            }
        } else if drops.count > strength {
            drops.removeLast(drops.count - strength)
        }
    }

    func update(date: Date, size: CGSize, speedMultiplier: Double = 1) {
        guard size.width > 0, size.height > 0 else {
            lastUpdate = date
            return
        }
        var delta = date.timeIntervalSince1970 - lastUpdate.timeIntervalSince1970
        let divisor = size.height / size.width

        if delta > 10 {
            delta = 0
        }

        for drop in drops {
            let radians = drop.direction.radians

            drop.x += cos(radians) * drop.speed * delta * divisor * speedMultiplier
            drop.y += sin(radians) * drop.speed * delta * speedMultiplier

            if drop.x < -0.2 {
                drop.x += 1.4
            } else if drop.x > 1.2 {
                drop.x -= 1.4
            }

            if drop.y > 1.2 {
                drop.x = Double.random(in: -0.2...1.2)
                drop.y -= 1.4
            }
        }

        lastUpdate = date
    }
}
