//
//  OnboardingStage.swift
//  Oscar°
//

import SwiftUI

/// The solid canvas behind the middle onboarding steps. Animated scenes
/// (sky, simulation, collage) stay inside a window at the top of the screen
/// and feather into this surface, so titles, copy, and controls always sit
/// on solid ground instead of the busy backdrop.
struct OnboardingStage: View {
    /// Fraction of the screen height at which the canvas becomes fully solid.
    static let heroFraction: CGFloat = 0.3
    /// Height of the gradient that dissolves the hero window into the canvas.
    static let featherHeight: CGFloat = 120

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: max(proxy.size.height * Self.heroFraction - Self.featherHeight, 0))

                LinearGradient(
                    colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Self.featherHeight)

                Color(.systemBackground)
            }
        }
        // Container edges are ignored but the keyboard is not: when it comes
        // up (manual city search), the whole stage measures against the space
        // above it, shrinking the hero window so the content keeps room.
        .ignoresSafeArea(.container)
        .allowsHitTesting(false)
    }
}

/// Lays a step out against the stage: the hero window stays clear for the
/// scene behind it, `content` starts where the canvas is fully solid.
struct OnboardingStageLayout<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            // The stage paints edge to edge, so the canvas position derives
            // from the full screen height — except the keyboard: it reports
            // as an oversized bottom inset, and the stage shrinks above it,
            // so it must not count as screen (the home indicator does).
            let bottomInset = proxy.safeAreaInsets.bottom
            let keyboardlessBottom = bottomInset > 100 ? 0 : bottomInset
            let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + keyboardlessBottom
            let canvasTop = screenHeight * OnboardingStage.heroFraction - proxy.safeAreaInsets.top

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: max(canvasTop, 0))

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

/// Standard entrance for canvas content: a fade with a small rise, staggered
/// per element by `delay` — the shared micro-choreography of every step.
struct OnboardingEntranceModifier: ViewModifier {
    let appeared: Bool
    let delay: Double
    var scale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .scaleEffect(appeared || reduceMotion ? 1 : scale)
            .animation(.spring(duration: 0.7, bounce: 0.2).delay(delay), value: appeared)
    }
}

extension View {
    func onboardingEntrance(_ appeared: Bool, delay: Double, scale: CGFloat = 1) -> some View {
        modifier(OnboardingEntranceModifier(appeared: appeared, delay: delay, scale: scale))
    }
}

#Preview {
    ZStack {
        OnboardingSceneView(scene: .day)
            .environment(Weather.mock)
        OnboardingStage()
    }
}
