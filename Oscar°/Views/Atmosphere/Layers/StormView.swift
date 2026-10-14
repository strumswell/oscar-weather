//
//  StormView.swift
//  Oscar°
//
//  Created by Paul Hudson on 03/02/2022.
//

import SwiftUI

struct StormView: View {
    let type: Storm.Contents
    let direction: Angle
    let strength: Int
    let pacing: SimulationPacing
    let speedMultiplier: Double
    @State private var storm: Storm

    var body: some View {
        TimelineView(.animation(minimumInterval: pacing.minimumInterval(base: nil), paused: pacing.isPaused)) { timeline in
            Canvas { context, size in
                storm.sync(strength: strength, direction: direction)
                storm.update(date: timeline.date, size: size, speedMultiplier: speedMultiplier)

                let resolvedImage = context.resolve(storm.image)
                for drop in storm.drops {
                    var contextCopy = context

                    let xPos = drop.x * size.width
                    let yPos = drop.y * size.height

                    contextCopy.opacity = drop.opacity
                    contextCopy.translateBy(x: xPos, y: yPos)
                    contextCopy.rotate(by: drop.direction + drop.rotation)
                    contextCopy.scaleBy(x: drop.xScale, y: drop.yScale)
                    contextCopy.draw(resolvedImage, at: .zero)
                }
            }
        }
        .ignoresSafeArea()
    }

    init(
        type: Storm.Contents,
        direction: Angle,
        strength: Int,
        pacing: SimulationPacing = .active,
        speedMultiplier: Double = 1
    ) {
        self.type = type
        self.direction = direction
        self.strength = strength
        self.pacing = pacing
        self.speedMultiplier = speedMultiplier
        _storm = State(initialValue: Storm(type: type, direction: direction, strength: strength))
    }
}

#Preview {
    StormView(type: .rain, direction: .zero, strength: 200)
}
