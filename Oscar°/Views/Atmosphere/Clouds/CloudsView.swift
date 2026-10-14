//
//  CloudsView.swift
//  Oscar°
//
//  Created by Paul Hudson on 12/11/2021.
//

import SwiftUI

struct CloudsView: View {
    let deck: CloudDeck
    var drift: Double = -4
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
                    let sink = band == .low ? size.height * 0.18 * (shadows[band] ?? 0) : 0
                    for cloud in cloudGroup.clouds where cloud.band == band {
                        let alpha = Double(cloud.visibility(coverage: coverage)) * profile.presence
                        guard alpha > 0.01,
                              let image = images[CloudSpriteKey(image: cloud.imageNumber, band: band)] else { continue }
                        let y = cloud.position.y + sink
                        let width = image.size.width * cloud.scale
                        guard y < size.height, y + image.size.height * cloud.scale > 0 else { continue }
                        let period = 2 * cloud.wrapDistance
                        var x = cloud.position.x
                        while x + width > 0 { x -= period }
                        x += period
                        context.opacity = alpha
                        while x < size.width {
                            context.translateBy(x: x, y: y)
                            context.scaleBy(x: cloud.scale, y: cloud.scale)
                            context.draw(image, at: .zero, anchor: .topLeading)
                            context.transform = .identity
                            x += period
                        }
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
