//
//  CloudsView.swift
//  Oscar°
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
                    guard let image = resolvedImages[cloud.imageNumber] else { continue }
                    // The deck is laid out for the full-screen sim — skip sprites
                    // fully outside a smaller canvas (location cards).
                    guard cloud.position.x < size.width,
                          cloud.position.y < size.height,
                          cloud.position.x + image.size.width * cloud.scale > 0,
                          cloud.position.y + image.size.height * cloud.scale > 0 else { continue }
                    let depth = scaleSpan < 0.01 ? 1.0 : (cloud.scale - minScale) / scaleSpan
                    context.opacity = cloudGroup.opacity * (0.55 + 0.45 * depth)
                    context.translateBy(x: cloud.position.x, y: cloud.position.y)
                    context.scaleBy(x: cloud.scale, y: cloud.scale)
                    context.draw(image, at: .zero, anchor: .topLeading)
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
    /// Tints compared at 8-bit precision: while the hourly stage tweens the
    /// sky, the exact colors differ every frame but the shaded bitmaps don't.
    private var tintKey: (SIMD4<Int32>, SIMD4<Int32>)?
    private var images: [Int: GraphicsContext.ResolvedImage] = [:]

    private static func key(_ color: Color, in environment: EnvironmentValues) -> SIMD4<Int32> {
        let resolved = color.resolve(in: environment)
        return SIMD4(
            Int32((resolved.red * 255).rounded()), Int32((resolved.green * 255).rounded()),
            Int32((resolved.blue * 255).rounded()), Int32((resolved.opacity * 255).rounded())
        )
    }

    func resolvedImages(
        for imageNumbers: [Int],
        topTint: Color,
        bottomTint: Color,
        in context: GraphicsContext
    ) -> [Int: GraphicsContext.ResolvedImage] {
        let needed = Set(imageNumbers)
        let key = (Self.key(topTint, in: context.environment), Self.key(bottomTint, in: context.environment))
        if let tintKey, tintKey == key, needed.isSubset(of: Set(images.keys)) {
            return images
        }

        tintKey = key
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
