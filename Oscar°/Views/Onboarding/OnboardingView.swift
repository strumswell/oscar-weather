//
//  OnboardingView.swift
//  Oscar°
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep = ScreenshotMode.onboardingStep ?? .welcome
    private let locationService = LocationService.shared

    var body: some View {
        ZStack {
            OnboardingBackgroundView(step: step)

            if let stageLayout {
                OnboardingStage(layout: stageLayout)
                    .transition(stageTransition)
                    .zIndex(2)
            }

            stepContent
                .transition(.onboardingSlide(reduceMotion: reduceMotion))
                .zIndex(3)
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeStep { advance(to: .features) }
        case .features:
            OnboardingFeaturesStep {
                advance(to: .afterFeatures(locationService: locationService))
            }
        case .location:
            OnboardingLocationStep { granted in
                if granted {
                    advance(to: .afterLocationResolved(locationService: locationService))
                } else {
                    advance(to: .manualLocation)
                }
            }
        case .manualLocation:
            OnboardingManualLocationStep {
                advance(to: .afterLocationResolved(locationService: locationService))
            }
        case .notifications:
            OnboardingNotificationsStep { advance(to: .afterNotifications) }
        case .crashReports:
            OnboardingCrashReportsStep { advance(to: .finale) }
        case .finale:
            OnboardingFinaleStep { OnboardingCoordinator.shared.complete() }
        }
    }

    private var stageLayout: OnboardingStage.Layout? {
        switch step {
        case .welcome, .finale: nil
        case .features: .tour
        case .notifications: .list
        case .location, .manualLocation, .crashReports: .question
        }
    }

    private var stageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(y: 44).combined(with: .opacity),
            removal: .opacity
        )
    }

    private func advance(to next: OnboardingStep) {
        withAnimation(.smooth(duration: 0.55)) {
            step = next
        }
    }
}

#Preview {
    OnboardingView()
        .environment(Weather.mock)
        .environment(Location())
        .preferredColorScheme(.dark)
}
