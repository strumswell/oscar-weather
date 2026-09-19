//
//  CloudGroup.swift
//  Oscar°
//
//  Created by Paul Hudson on 12/11/2021.
//

import Foundation

/// One fixed sprite deck for all three bands; cover only changes which
/// sprites show, never the layout, so tweened hours don't reshuffle the sky.
final class CloudGroup {
    /// Built on first draw, not in `init`: the `@State` default is evaluated
    /// on every parent body pass (per frame under a scrub tween).
    private(set) lazy var clouds: [Cloud] = Self.makeDeck()
    private var lastUpdate = Date.now

    /// `drift`: low-band points per second at scale 1, signed (negative = left).
    func update(date: Date, drift: Double) {
        var delta = date.timeIntervalSince1970 - lastUpdate.timeIntervalSince1970
        if delta > 10 {
            delta = 0
        }

        for cloud in clouds {
            cloud.position.x += delta * drift * cloud.band.profile.driftFactor * cloud.scale * cloud.driftJitter

            let offScreenDistance = max(620, 420 * cloud.scale)
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
                // Thresholds spread evenly across the band, size grows with the
                // threshold: the first sprites to appear are the small ones.
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
