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

    // @State-as-cache: resolving + gradient-shading the cloud bitmaps is one of the more
    // expensive Canvas operations and depends only on the (constant) tints — do it once and
    // reuse across frames instead of rebuilding the dictionary every draw.
    @State private var imageCache = CloudImageCache()

    var body: some View {
        TimelineView(.animation(minimumInterval: pacing.minimumInterval(base: 1.0 / 30.0), paused: pacing.isPaused)) { timeline in
            Canvas { context, size in
                cloudGroup.update(date: timeline.date)

                let resolvedImages = imageCache.resolvedImages(
                    for: cloudGroup.clouds.map(\.imageNumber),
                    topTint: topTint,
                    bottomTint: bottomTint,
                    in: context
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

/// Caches resolved, gradient-shaded cloud bitmaps so the Canvas resolves them only when the
/// tints (or the set of cloud images) change, not every frame. Held via `@State` — mutating its
/// contents inside the draw closure is reference mutation, not view-state mutation.
private final class CloudImageCache {
    private var topTint: Color?
    private var bottomTint: Color?
    private var images: [Int: GraphicsContext.ResolvedImage] = [:]

    func resolvedImages(
        for imageNumbers: [Int],
        topTint: Color,
        bottomTint: Color,
        in context: GraphicsContext
    ) -> [Int: GraphicsContext.ResolvedImage] {
        let needed = Set(imageNumbers)
        if self.topTint == topTint,
           self.bottomTint == bottomTint,
           needed.isSubset(of: Set(images.keys)) {
            return images
        }

        self.topTint = topTint
        self.bottomTint = bottomTint
        images = Dictionary(uniqueKeysWithValues: needed.map { i -> (Int, GraphicsContext.ResolvedImage) in
            var resolved = context.resolve(Image("cloud\(i)"))
            resolved.shading = .linearGradient(
                Gradient(colors: [topTint, bottomTint]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: resolved.size.height)
            )
            return (i, resolved)
        })
        return images
    }
}

#Preview {
    CloudsView(thickness: .regular, topTint: .white, bottomTint: .white)
        .background(.blue)
}
