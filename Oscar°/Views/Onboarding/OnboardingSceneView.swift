//
//  OnboardingSceneView.swift
//  Oscar°
//

import SwiftUI

struct OnboardingSceneView: View {
    enum Scene {
        case day
        case night
        case storm
    }

    let scene: Scene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let moonX = 0.72
    private static let moonY = 0.15

    var body: some View {
        let snapshot = snapshot
        let pacing: SimulationPacing = reduceMotion ? .still : .active

        GeometryReader { proxy in
            ZStack {
                AtmosphereSkyShaderView(snapshot: snapshot, size: proxy.size, pacing: pacing)

                if scene == .night {
                    StarsView(
                        pacing: pacing,
                        occlusionCenter: CGPoint(
                            x: proxy.size.width * Self.moonX,
                            y: proxy.size.height * Self.moonY
                        ),
                        occlusionRadius: MoonView.diameter / 2 + 8,
                        opacityOverride: 1,
                        meteorDelayRange: 3...7
                    )

                    MoonView(
                        phase: 0.12,
                        altitudeProgress: 0.55,
                        xFraction: Self.moonX,
                        yFraction: Self.moonY,
                        isSouthernHemisphere: false
                    )
                }

                if scene == .day {
                    SunView(progress: 0.45)
                }

                if scene != .night {
                    CloudsView(
                        deck: CloudDeck(total: scene == .storm ? 1 : 0.2),
                        drift: scene == .storm ? -10 : -3,
                        lightDirection: snapshot.cloudLightDirection,
                        topTint: AtmosphereSampler.cloudTopTint(snapshot: snapshot),
                        bottomTint: AtmosphereSampler.cloudBottomTint(snapshot: snapshot),
                        pacing: pacing
                    )
                }

                if scene == .storm {
                    StormView(type: .rain, direction: .degrees(-12), strength: 140, pacing: pacing)
                        .opacity(reduceMotion ? 0.55 : 1)

                    LightningFlashView(pacing: pacing)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var snapshot: AtmosphereSnapshot {
        switch scene {
        case .day: .fallback
        case .night: .onboardingNight
        case .storm: .onboardingStorm
        }
    }
}

extension AtmosphereSnapshot {
    static let onboardingNight = AtmosphereSnapshot(
        timestamp: Date.now.timeIntervalSince1970,
        timeOfDay: 0.97,
        sunElevation: -0.35,
        phase: 0,
        nightAmount: 1,
        condition: .clear,
        cloudCoverage: 0,
        cloudDensity: 0,
        precipitationAmount: 0,
        snowfallAmount: 0,
        precipitationIntensity: 0,
        snowfallIntensity: 0,
        thunderIntensity: 0,
        haze: 0.04,
        turbidity: 0.15,
        windSpeed: 0,
        windDirection: 0,
        aqiHaze: 0
    )

    static let onboardingStorm = AtmosphereSnapshot(
        timestamp: Date.now.timeIntervalSince1970,
        timeOfDay: 0.58,
        sunElevation: 0.12,
        phase: 1,
        nightAmount: 0.22,
        condition: .thunderstorm,
        cloudCoverage: 0.96,
        cloudDensity: 0.95,
        precipitationAmount: 5,
        snowfallAmount: 0,
        precipitationIntensity: 0.5,
        snowfallIntensity: 0,
        thunderIntensity: 0.8,
        haze: 0.42,
        turbidity: 0.65,
        windSpeed: 0.35,
        windDirection: 4.0,
        aqiHaze: 0
    )
}

private struct LightningFlashView: View {
    var pacing: SimulationPacing = .active

    var body: some View {
        if pacing == .still {
            Color.clear
                .allowsHitTesting(false)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Rectangle()
                    .fill(Color(red: 0.85, green: 0.9, blue: 1.0))
                    .opacity(Self.flashOpacity(at: timeline.date.timeIntervalSinceReferenceDate))
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    static func flashOpacity(at time: TimeInterval) -> Double {
        let cadence = 1.5
        let bucket = (time / cadence).rounded(.down)
        let hash = (sin(bucket * 127.1 + 311.7) * 43758.5453).truncatingRemainder(dividingBy: 1)
        guard abs(hash) > 0.45 else { return 0 }

        let phase = time / cadence - bucket
        let strike = pow(max(0, 1 - phase * 3.2), 2)
        let flicker = 0.6 * pow(max(0, 1 - abs(phase - 0.22) * 6), 2)
        return min(1, strike + flicker) * 0.5
    }
}

#Preview("Night") {
    OnboardingSceneView(scene: .night)
        .environment(Weather.mock)
}

#Preview("Storm") {
    OnboardingSceneView(scene: .storm)
        .environment(Weather.mock)
}
