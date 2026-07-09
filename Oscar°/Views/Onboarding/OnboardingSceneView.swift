//
//  OnboardingSceneView.swift
//  Oscar°
//

import SwiftUI

/// Hand-built weather dioramas behind the onboarding steps, composed from the
/// real simulation's primitives with fixed snapshots — the live mapper can't
/// be steered, since sun position and conditions come from wall clock and
/// forecast. The flow walks through a day: noon, starry night, storm.
struct OnboardingSceneView: View {
    enum Scene {
        /// Idealized clear noon: the postcard behind welcome and features.
        case day
        /// Clear night: dense twinkling stars, meteors, a waxing crescent.
        case night
        /// Heavy thunderstorm: dark deck, lightning, slanted rain.
        case storm
    }

    let scene: Scene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Crescent position, kept inside the hero window above the canvas.
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

                // A clear night stays cloudless — the stars are the show.
                if scene != .night {
                    CloudsView(
                        thickness: scene == .storm ? .ultra : .thin,
                        topTint: AtmosphereSampler.cloudTopTint(snapshot: snapshot),
                        bottomTint: AtmosphereSampler.cloudBottomTint(snapshot: snapshot),
                        pacing: pacing
                    )
                }

                if scene == .storm {
                    StormView(type: .rain, direction: .degrees(-12), strength: 140, pacing: pacing)
                        .opacity(reduceMotion ? 0.55 : 1)

                    // The shader's lightning lives in the sky layer, which the
                    // near-total deck hides (and it strikes ~every 10 s) — a
                    // real storm reads as the whole deck lighting up, so the
                    // glow renders above clouds and rain, and often.
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
    /// A deep, cloudless night: sun far below the horizon so the sky sits at
    /// the shader's darkest palette and the star field carries the scene.
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
        humidity: 0.4,
        pressure: 1,
        haze: 0.04,
        turbidity: 0.15,
        windSpeed: 0,
        windDirection: 0,
        aqiHaze: 0
    )

    /// A severe afternoon thunderstorm: near-total cover, a dense dark deck
    /// with a hint of hail-green, lightning driving the sky shader's flash
    /// timeline, and wind-slanted rain.
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
        humidity: 0.85,
        pressure: 0.96,
        haze: 0.42,
        turbidity: 0.65,
        windSpeed: 0.35,
        windDirection: 4.0,
        aqiHaze: 0
    )
}

/// Frequent flashes above the storm's cloud deck: hash-triggered strikes every
/// couple of seconds, each a sharp pulse with a flicker afterglow — the same
/// cadence math as the sky shader, tuned far more frequent for the diorama.
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

    /// Strikes in ~55% of 1.5-second buckets — a flash every 2–3 seconds on
    /// average — with a fast quadratic decay and a weaker second flicker.
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
