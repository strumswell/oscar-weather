//
//  CloudGroup.swift
//  Oscar°
//
//  Created by Paul Hudson on 12/11/2021.
//

import Foundation

final class CloudGroup {
    private(set) lazy var clouds: [Cloud] = Self.makeDeck()
    private var lastUpdate = Date.now

    func update(date: Date, drift: Double) {
        var delta = date.timeIntervalSince1970 - lastUpdate.timeIntervalSince1970
        if delta > 10 {
            delta = 0
        }

        for cloud in clouds {
            cloud.position.x += delta * drift * cloud.band.profile.driftFactor * cloud.scale * cloud.driftJitter

            let offScreenDistance = cloud.wrapDistance
            if cloud.position.x < -offScreenDistance {
                cloud.position.x = offScreenDistance
            } else if cloud.position.x > offScreenDistance {
                cloud.position.x = -offScreenDistance
            }
        }

        lastUpdate = date
    }

    private static func makeDeck() -> [Cloud] {
        var clouds = [Cloud]()
        for band in Cloud.Band.allCases {
            let profile = band.profile
            for i in 0..<profile.count {
                let threshold = (Float(i) + Float.random(in: 0.2...0.8)) / Float(profile.count)
                let scaleSpan = profile.scale.upperBound - profile.scale.lowerBound
                let scale = profile.scale.lowerBound + scaleSpan * (Double(threshold) * 0.7 + Double.random(in: 0...0.3))
                clouds.append(Cloud(
                    band: band,
                    imageNumber: profile.imagePool[i % profile.imagePool.count],
                    scale: scale,
                    threshold: threshold,
                    position: CGPoint(x: Double.random(in: -620...620), y: Double.random(in: profile.yRange))
                ))
            }
        }
        return clouds
    }
}
