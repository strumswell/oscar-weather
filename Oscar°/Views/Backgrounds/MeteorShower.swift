//
//  MeteorShower.swift
//  Weather
//
//  Created by Paul Hudson on 10/07/2022.
//

import SwiftUI

class MeteorShower {
    var meteors = Set<Meteor>()
    var lastUpdate = Date.now

    /// Seconds between spawns; the onboarding night diorama shortens it so a
    /// meteor reliably streaks past while the step is on screen.
    let delayRange: ClosedRange<Double>
    var lastCreationDate = Date.now
    var nextCreationDelay: Double

    init(delayRange: ClosedRange<Double> = 5...10) {
        self.delayRange = delayRange
        nextCreationDelay = .random(in: delayRange)
    }

    func update(date: Date, size: CGSize) {
        let elapsed = date.timeIntervalSince1970 - lastUpdate.timeIntervalSince1970
        let delta = elapsed > 10 ? 0 : elapsed

        if lastCreationDate + nextCreationDelay < .now {
            createMeteor(in: size)
        }

        // Collect spent meteors and remove them after the loop — mutating the Set mid-iteration
        // triggers a copy-on-write on every removal and is fragile semantics.
        var spent: [Meteor] = []
        for meteor in meteors {
            if meteor.isMovingRight {
                meteor.x += delta * meteor.speed
            } else {
                meteor.x -= delta * meteor.speed
            }

            meteor.speed -= delta * 900

            if meteor.speed < 0 {
                spent.append(meteor)
            } else if meteor.length < 100 {
                meteor.length += delta * 300
            }
        }
        meteors.subtract(spent)
        
        lastUpdate = date
    }

    func createMeteor(in size: CGSize) {
        let meteor: Meteor

        if Bool.random() {
            meteor = Meteor(x: 0, y: Double.random(in: 100...200), isMovingRight: true)
        } else {
            meteor = Meteor(x: size.width, y: Double.random(in: 100...200), isMovingRight: false)
        }

        meteors.insert(meteor)
        lastCreationDate = .now
        nextCreationDelay = .random(in: delayRange)
    }
}
