//
//  CloudGroup.swift
//  Weather
//
//  Created by Paul Hudson on 12/11/2021.
//

import Foundation

class CloudGroup {
    var clouds = [Cloud]()
    let opacity: Double
    var lastUpdate = Date.now

    init(thickness: Cloud.Thickness) {
        let profile = CloudProfile(thickness: thickness)
        opacity = profile.opacity

        for i in 0..<profile.count {
            let scale = Double.random(in: profile.scale)
            let imageNumber = profile.imagePool[i % profile.imagePool.count]

            let cloud = Cloud(
                imageNumber: imageNumber,
                scale: scale,
                xRange: profile.xRange,
                yRange: profile.yRange,
                speedRange: profile.speed
            )
            clouds.append(cloud)
        }
    }

    func update(date: Date) {
        var delta = date.timeIntervalSince1970 - lastUpdate.timeIntervalSince1970
        
        
        if delta > 10 {
            delta = 0
        }

        for cloud in clouds {
            cloud.position.x -= delta * cloud.speed

            let offScreenDistance = max(620, 420 * cloud.scale)

            if cloud.position.x < -offScreenDistance {
                cloud.position.x = offScreenDistance
            }
        }

        lastUpdate = date
    }
}

private struct CloudProfile {
    let count: Int
    let opacity: Double
    let scale: ClosedRange<Double>
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>
    let speed: ClosedRange<Double>
    let imagePool: [Int]

    init(thickness: Cloud.Thickness) {
        switch thickness {
        case .none:
            count = 0
            opacity = 1
            scale = 1...1
            xRange = -400...400
            yRange = -50...200
            speed = 4...12
            imagePool = [1]

        case .thin:
            count = 6
            opacity = 0.56
            scale = 0.26...0.46
            xRange = -460...460
            yRange = -70...130
            speed = 2...6
            imagePool = [1, 2, 5, 6, 6]

        case .light:
            count = 11
            opacity = 0.74
            scale = 0.42...0.76
            xRange = -500...500
            yRange = -95...210
            speed = 2...7
            imagePool = [1, 2, 4, 5, 6, 6, 0]

        case .regular:
            count = 14
            opacity = 0.82
            scale = 0.54...0.92
            xRange = -540...540
            yRange = -110...240
            speed = 2...8
            imagePool = [1, 2, 4, 5, 6, 6, 0, 3]

        case .thick:
            count = 24
            opacity = 0.94
            scale = 0.78...1.28
            xRange = -580...580
            yRange = -140...280
            speed = 2...9
            imagePool = [0, 2, 3, 4, 4, 5, 6, 6, 1]

        case .ultra:
            count = 36
            opacity = 1
            scale = 0.95...1.55
            xRange = -620...620
            yRange = -170...320
            speed = 2...10
            imagePool = [0, 2, 3, 4, 4, 5, 6, 6, 1, 7]
        }
    }
}
