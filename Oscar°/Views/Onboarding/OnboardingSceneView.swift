//
//  OnboardingSceneView.swift
//  Oscar°
//

import SwiftUI

struct OnboardingSceneView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let snapshot = AtmosphereSnapshot.fallback
        let pacing: SimulationPacing = reduceMotion ? .still : .active

        GeometryReader { proxy in
            ZStack {
                AtmosphereSkyShaderView(snapshot: snapshot, size: proxy.size, pacing: pacing)

                SunView(progress: 0.45)

                CloudsView(
                    deck: CloudDeck(total: 0.2),
                    drift: -3,
                    lightDirection: snapshot.cloudLightDirection,
                    topTint: AtmosphereSampler.cloudTopTint(snapshot: snapshot),
                    bottomTint: AtmosphereSampler.cloudBottomTint(snapshot: snapshot),
                    pacing: pacing
                )
            }
        }
        .ignoresSafeArea()
    }
}
