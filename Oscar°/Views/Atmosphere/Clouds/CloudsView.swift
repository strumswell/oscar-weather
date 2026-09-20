//
//  CloudsView.swift
//  Oscar°
//
//  Created by Paul Hudson on 12/11/2021.
//

import SwiftUI

struct CloudsView: View {
    let deck: CloudDeck
    /// Low-band drift in points per second at scale 1; negative moves left.
    var drift: Double = -4
    /// Sun → deck direction in screen fractions; nil shades top-down.
    var lightDirection: CGVector? = nil
    let topTint: Color
    let bottomTint: Color
    var pacing: SimulationPacing = .active

    @State private var cloudGroup = CloudGroup()
    @State private var imageCache = CloudImageCache()

    var body: some View {
        TimelineView(.animation(minimumInterval: pacing.minimumInterval(base: 1.0 / 30.0), paused: pacing.isPaused)) { timeline in
            Canvas { context, size in
                cloudGroup.update(date: timeline.date, drift: drift)

                // Past ~55 % cover a band closes into a lid. The lid itself stays
                // bright (it is what the daylight comes through); only the sprites
                // hanging under one take its shadow, so fragments read as dark
                // scud against a bright lid instead of dissolving into it.
                var veils: [Cloud.Band: Double] = [:]
                var shadows: [Cloud.Band: Double] = [:]
                var lidAbove = 0.0
                for band in Cloud.Band.allCases {
                    let veil = Double(AtmosphereWeatherMapper.smoothstep(0.55, 1, deck[band])) * band.profile.veil
                    veils[band] = veil
                    lidAbove = 1 - (1 - lidAbove) * (1 - veil)
                    shadows[band] = lidAbove
                }

                let images = imageCache.resolvedImages(
                    for: cloudGroup.clouds,
                    topTint: topTint,
                    bottomTint: bottomTint,
                    lightDirection: lightDirection,
                    shadows: shadows,
                    in: context
                )

                for band in Cloud.Band.allCases {
                    let profile = band.profile
                    // Overcast lids are brightest overhead and fall off toward the
                    // horizon (CIE overcast sky, roughly 3:1), so the veil is a
                    // top-lit gradient down to the band's shading floor.
                    if let veil = veils[band], veil > 0.01 {
                        let floor = topTint.mix(with: bottomTint, by: profile.shading)
                        context.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .linearGradient(
                                Gradient(colors: [topTint.opacity(veil), floor.opacity(veil)]),
                                startPoint: .zero,
                                endPoint: CGPoint(x: 0, y: size.height)
                            )
                        )
                    }

                    let coverage = deck[band]
                    // Under a lid the ragged scud hangs in the lower sky, not
                    // across all of it: the low band sinks with the lid amount.
                    let sink = band == .low ? size.height * 0.18 * (shadows[band] ?? 0) : 0
                    for cloud in cloudGroup.clouds where cloud.band == band {
                        // No translucency at low cover: scattered cumulus are as solid
                        // as a full deck, there are just fewer of them.
                        let alpha = Double(cloud.visibility(coverage: coverage)) * profile.presence
                        guard alpha > 0.01,
                              let image = images[CloudSpriteKey(image: cloud.imageNumber, band: band)] else { continue }
                        // The deck is laid out for the full-screen sim — skip sprites
                        // fully outside a smaller canvas (location cards).
                        let y = cloud.position.y + sink
                        guard cloud.position.x < size.width,
                              y < size.height,
                              cloud.position.x + image.size.width * cloud.scale > 0,
                              y + image.size.height * cloud.scale > 0 else { continue }
                        context.opacity = alpha
                        context.translateBy(x: cloud.position.x, y: y)
                        context.scaleBy(x: cloud.scale, y: cloud.scale)
                        context.draw(image, at: .zero, anchor: .topLeading)
                        context.transform = .identity
                    }
                }
            }
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    CloudsView(deck: CloudDeck(total: 0.6), topTint: .white, bottomTint: .white)
        .background(.blue)
}
