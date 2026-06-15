//
//  CloudsView.swift
//  Weather
//
//  Created by Paul Hudson on 12/11/2021.
//

import SwiftUI

struct CloudsView: View {
    @State private var cloudGroup: CloudGroup
    let topTint: Color
    let bottomTint: Color
    let pacing: SimulationPacing

    var body: some View {
        TimelineView(.animation(minimumInterval: pacing.minimumInterval(base: 1.0 / 30.0), paused: pacing.isPaused)) { timeline in
            Canvas { context, size in
                cloudGroup.update(date: timeline.date)

                let usedImageNumbers = Set(cloudGroup.clouds.map(\.imageNumber))
                let resolvedImages = Dictionary(
                    uniqueKeysWithValues: usedImageNumbers.map { i -> (Int, GraphicsContext.ResolvedImage) in
                        let sourceImage = Image("cloud\(i)")
                        var resolved = context.resolve(sourceImage)
                        
                        resolved.shading = .linearGradient(
                            Gradient(colors: [topTint, bottomTint]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: 0, y: resolved.size.height)
                        )
                        
                        return (i, resolved)
                    }
                )

                // Atmospheric perspective: smaller (farther) clouds sit
                // closer to the sky, big near ones keep full presence.
                let scales = cloudGroup.clouds.map(\.scale)
                let minScale = scales.min() ?? 1
                let scaleSpan = (scales.max() ?? 1) - minScale

                for cloud in cloudGroup.clouds {
                    let depth = scaleSpan < 0.01 ? 1.0 : (cloud.scale - minScale) / scaleSpan
                    context.opacity = cloudGroup.opacity * (0.55 + 0.45 * depth)
                    context.translateBy(x: cloud.position.x, y: cloud.position.y)
                    context.scaleBy(x: cloud.scale, y: cloud.scale)
                    if let image = resolvedImages[cloud.imageNumber] {
                        context.draw(image, at: .zero, anchor: .topLeading)
                    }
                    context.transform = .identity
                }
            }
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    init(
        thickness: Cloud.Thickness,
        topTint: Color,
        bottomTint: Color,
        pacing: SimulationPacing = .active
    ) {
        _cloudGroup = State(initialValue: CloudGroup(thickness: thickness))
        self.topTint = topTint
        self.bottomTint = bottomTint
        self.pacing = pacing
    }
}

struct CloudsView_Previews: PreviewProvider {
    static var previews: some View {
        CloudsView(thickness: .regular, topTint: .white, bottomTint: .white)
            .background(.blue)
    }
}
