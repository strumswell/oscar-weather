//
//  CloudImageCache.swift
//  Oscar°
//

import SwiftUI

struct CloudSpriteKey: Hashable {
    let image: Int
    let band: Cloud.Band
}

final class CloudImageCache {
    static let lidShadow = 0.18

    private var key: (SIMD4<Int32>, SIMD4<Int32>, Int, SIMD3<Int32>)?
    private var images: [CloudSpriteKey: GraphicsContext.ResolvedImage] = [:]

    func resolvedImages(
        for clouds: [Cloud],
        topTint: Color,
        bottomTint: Color,
        lightDirection: CGVector?,
        shadows: [Cloud.Band: Double],
        in context: GraphicsContext
    ) -> [CloudSpriteKey: GraphicsContext.ResolvedImage] {
        let light = lightDirection ?? CGVector(dx: 0, dy: 1)
        let angleStep = Int((atan2(light.dy, light.dx) / (.pi / 18)).rounded())
        let shadowSteps = SIMD3<Int32>(Cloud.Band.allCases.map { Int32(((shadows[$0] ?? 0) * 16).rounded()) })
        let key = (Self.key(topTint, in: context.environment), Self.key(bottomTint, in: context.environment), angleStep, shadowSteps)
        if let cached = self.key, cached == key {
            return images
        }

        self.key = key
        images = [:]
        for cloud in clouds {
            let sprite = CloudSpriteKey(image: cloud.imageNumber, band: cloud.band)
            guard images[sprite] == nil else { continue }
            var resolved = context.resolve(Image("cloud\(sprite.image)"))
            let center = CGPoint(x: resolved.size.width / 2, y: resolved.size.height / 2)
            let reach = (abs(light.dx) * resolved.size.width + abs(light.dy) * resolved.size.height) / 2
            let lit = topTint.mix(with: .black, by: Self.lidShadow * (shadows[sprite.band] ?? 0))
            resolved.shading = .linearGradient(
                Gradient(colors: [lit, lit.mix(with: bottomTint, by: sprite.band.profile.shading)]),
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
