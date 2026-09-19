//
//  CloudImageCache.swift
//  Oscar°
//

import SwiftUI

struct CloudSpriteKey: Hashable {
    let image: Int
    let band: Cloud.Band
}

/// Caches resolved, gradient-shaded cloud bitmaps so the Canvas resolves them
/// only when the tints or the light angle change, not every frame. Held via
/// `@State` — mutating its contents inside the draw closure is reference
/// mutation, not view-state mutation.
final class CloudImageCache {
    /// Tints compared at 8-bit precision, the light angle in 10° steps: while
    /// the hourly stage tweens the sky, the exact values differ every frame
    /// but the shaded bitmaps don't.
    private var key: (SIMD4<Int32>, SIMD4<Int32>, Int)?
    private var images: [CloudSpriteKey: GraphicsContext.ResolvedImage] = [:]

    /// The deck's sprite set is fixed, so a cache hit needs no membership check.
    func resolvedImages(
        for clouds: [Cloud],
        topTint: Color,
        bottomTint: Color,
        lightDirection: CGVector?,
        in context: GraphicsContext
    ) -> [CloudSpriteKey: GraphicsContext.ResolvedImage] {
        let light = lightDirection ?? CGVector(dx: 0, dy: 1)
        let angleStep = Int((atan2(light.dy, light.dx) / (.pi / 18)).rounded())
        let key = (Self.key(topTint, in: context.environment), Self.key(bottomTint, in: context.environment), angleStep)
        if let cached = self.key, cached == key {
            return images
        }

        self.key = key
        images = [:]
        for cloud in clouds {
            let sprite = CloudSpriteKey(image: cloud.imageNumber, band: cloud.band)
            guard images[sprite] == nil else { continue }
            var resolved = context.resolve(Image("cloud\(sprite.image)"))
            // Lit edge (top tint) faces the sun, shadow edge faces away; the
            // gradient spans the sprite's extent along the light direction and
            // only goes as dark as the band's shading allows.
            let center = CGPoint(x: resolved.size.width / 2, y: resolved.size.height / 2)
            let reach = (abs(light.dx) * resolved.size.width + abs(light.dy) * resolved.size.height) / 2
            resolved.shading = .linearGradient(
                Gradient(colors: [topTint, topTint.mix(with: bottomTint, by: sprite.band.profile.shading)]),
                startPoint: CGPoint(x: center.x - light.dx * reach, y: center.y - light.dy * reach),
                endPoint: CGPoint(x: center.x + light.dx * reach, y: center.y + light.dy * reach)
            )
            images[sprite] = resolved
        }
        return images
    }

    private static func key(_ color: Color, in environment: EnvironmentValues) -> SIMD4<Int32> {
        let resolved = color.resolve(in: environment)
        return SIMD4(
            Int32((resolved.red * 255).rounded()), Int32((resolved.green * 255).rounded()),
            Int32((resolved.blue * 255).rounded()), Int32((resolved.opacity * 255).rounded())
        )
    }
}
