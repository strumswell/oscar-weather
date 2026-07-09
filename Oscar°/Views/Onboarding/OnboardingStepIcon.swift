//
//  OnboardingStepIcon.swift
//  Oscar°
//

import SwiftUI

/// The bare SF Symbol that crowns a step's title on the stage canvas.
struct OnboardingStepIcon: View {
    let systemImage: String
    let tint: Color
    var wiggles = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 38, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint.gradient)
            .symbolEffect(
                .wiggle,
                options: .repeat(.periodic(delay: 2.5)),
                isActive: wiggles && !reduceMotion
            )
            .accessibilityHidden(true)
    }
}
