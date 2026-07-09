//
//  OnboardingView.swift
//  Oscar°
//

import SwiftUI

/// The multi-step first-launch flow: welcome → feature tour → location →
/// (manual city) → (notifications) → finale. Steps share a background that
/// starts as a picture-book sky and becomes the live weather simulation once
/// a real location exists; between welcome and finale a solid canvas covers
/// the lower two thirds so text never sits on the animated backdrop.
struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep = .welcome
    private let locationService = LocationService.shared

    var body: some View {
        ZStack {
            OnboardingBackgroundView(step: step)

            // The collage lives beneath the stage canvas, so the feather
            // gradient dissolves the drifting cards into solid ground.
            if step == .features {
                OnboardingCollage()
                    .transition(collageTransition)
                    .zIndex(1)
            }

            if showsStage {
                OnboardingStage()
                    .transition(stageTransition)
                    .zIndex(2)
            }

            stepContent
                .zIndex(3)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: step)
    }

    @ViewBuilder private var stepContent: some View {
        ZStack {
            switch step {
            case .welcome:
                OnboardingWelcomeStep { advance(to: .features) }
                    .transition(stepTransition)
            case .features:
                OnboardingFeaturesStep {
                    advance(to: .afterFeatures(locationService: locationService))
                }
                .transition(stepTransition)
            case .location:
                OnboardingLocationStep { granted in
                    if granted {
                        advance(to: .afterLocationResolved(locationService: locationService))
                    } else {
                        advance(to: .manualLocation)
                    }
                }
                .transition(stepTransition)
            case .manualLocation:
                OnboardingManualLocationStep {
                    advance(to: .afterLocationResolved(locationService: locationService))
                }
                .transition(stepTransition)
            case .notifications:
                OnboardingNotificationsStep { advance(to: .finale) }
                    .transition(stepTransition)
            case .finale:
                OnboardingFinaleStep { OnboardingCoordinator.shared.complete() }
                    .transition(stepTransition)
            }
        }
    }

    /// The canvas spans every step between the full-bleed welcome and finale.
    private var showsStage: Bool {
        switch step {
        case .welcome, .finale: false
        default: true
        }
    }

    /// A soft push: the incoming step slides a short distance out of a slight
    /// defocus while the outgoing one lags behind it — a crossfade when motion
    /// is reduced.
    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: StepSlideModifier(offsetX: 90, opacity: 0, blur: 6),
                identity: StepSlideModifier(offsetX: 0, opacity: 1, blur: 0)
            ),
            removal: .modifier(
                active: StepSlideModifier(offsetX: -110, opacity: 0, blur: 6),
                identity: StepSlideModifier(offsetX: 0, opacity: 1, blur: 0)
            )
        )
    }

    /// The canvas rises softly out of the welcome screen and dissolves under
    /// the finale's frost.
    private var stageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: StageRiseModifier(offsetY: 44, opacity: 0),
                identity: StageRiseModifier(offsetY: 0, opacity: 1)
            ),
            removal: .opacity
        )
    }

    /// The collage settles in from a slight zoom and drifts off up-wind once
    /// the feature step ends.
    private var collageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: CollageDriftModifier(scale: 1.05, opacity: 0),
                identity: CollageDriftModifier()
            ),
            removal: .modifier(
                active: CollageDriftModifier(offset: CGSize(width: -80, height: -120), blur: 8, opacity: 0),
                identity: CollageDriftModifier()
            )
        )
    }

    private func advance(to next: OnboardingStep) {
        withAnimation(.smooth(duration: 0.55)) {
            step = next
        }
    }
}

private struct StepSlideModifier: ViewModifier {
    let offsetX: CGFloat
    let opacity: Double
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: offsetX)
            .opacity(opacity)
            .blur(radius: blur)
    }
}

private struct StageRiseModifier: ViewModifier {
    let offsetY: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(y: offsetY)
            .opacity(opacity)
    }
}

private struct CollageDriftModifier: ViewModifier {
    var offset: CGSize = .zero
    var scale: CGFloat = 1
    var blur: CGFloat = 0
    var opacity: Double = 1

    func body(content: Content) -> some View {
        content
            .offset(offset)
            .scaleEffect(scale)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

#Preview {
    OnboardingView()
        .environment(Weather.mock)
        .environment(Location())
        .preferredColorScheme(.dark)
}
