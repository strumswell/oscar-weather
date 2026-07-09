//
//  OnboardingGate.swift
//  Oscar°
//

import SwiftUI

/// Mounts the onboarding flow above NowView on first launch and when replayed
/// from settings; dismissal is a soft zoom-through that unveils the app.
struct OnboardingGate: View {
    private let coordinator = OnboardingCoordinator.shared

    var body: some View {
        ZStack {
            if coordinator.isPresented {
                OnboardingView()
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .scale(scale: 1.08))
                        )
                    )
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.7), value: coordinator.isPresented)
    }
}
