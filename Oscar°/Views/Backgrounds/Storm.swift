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
    private let type: Contents

    init(type: Contents, direction: Angle, strength: Int) {
        self.type = type
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

    /// Matches the live drop count to the latest forecast intensity without
    /// resetting drops that are already falling. New drops pick up the
    /// current wind direction; existing ones keep theirs.
    func sync(strength: Int, direction: Angle) {
        if drops.count < strength {
            for _ in drops.count..<strength {
                drops.append(StormDrop(type: type, direction: direction + .degrees(90)))
            }
        } else if drops.count > strength {
            drops.removeLast(drops.count - strength)
        }
    }

    /// `speedMultiplier` compensates small containers: drop speed is a fraction
    /// of the view height per second, so the same drop that streaks across the
    /// fullscreen sim crawls inside a ~100pt card without a boost.
    func update(date: Date, size: CGSize, speedMultiplier: Double = 1) {
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
