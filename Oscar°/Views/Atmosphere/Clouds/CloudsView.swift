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

                let images = imageCache.resolvedImages(
                    for: cloudGroup.clouds,
                    topTint: topTint,
                    bottomTint: bottomTint,
                    lightDirection: lightDirection,
                    in: context
                )

                for cloud in cloudGroup.clouds {
                    let coverage = deck[cloud.band]
                    let alpha = Double(cloud.visibility(coverage: coverage))
                        * cloud.band.profile.presence
                        * (0.6 + 0.4 * Double(coverage))
                    guard alpha > 0.01,
                          let image = images[CloudSpriteKey(image: cloud.imageNumber, band: cloud.band)] else { continue }
                    // The deck is laid out for the full-screen sim — skip sprites
                    // fully outside a smaller canvas (location cards).
                    guard cloud.position.x < size.width,
                          cloud.position.y < size.height,
                          cloud.position.x + image.size.width * cloud.scale > 0,
                          cloud.position.y + image.size.height * cloud.scale > 0 else { continue }
                    context.opacity = alpha
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
}

#Preview {
    CloudsView(deck: CloudDeck(total: 0.6), topTint: .white, bottomTint: .white)
        .background(.blue)
}
