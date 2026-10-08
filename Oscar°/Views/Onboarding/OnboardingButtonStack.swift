//
//  OnboardingButtonStack.swift
//  Oscar°
//

import SwiftUI

/// Bottom action area shared by all onboarding steps: a prominent glass CTA
/// and an optional quiet secondary action beneath it.
struct OnboardingButtonStack: View {
    let primaryTitle: LocalizedStringKey
    var primaryDisabled = false
    let primaryAction: () -> Void
    var secondaryTitle: LocalizedStringKey? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Button(action: primaryAction) {
                Text(primaryTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .disabled(primaryDisabled)

            if let secondaryTitle, let secondaryAction {
                // Text only: a second glass capsule competed with the primary.
                Button(action: secondaryAction) {
                    Text(secondaryTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, OnboardingStage.edgePadding)
        .frame(maxWidth: OnboardingStage.contentMaxWidth)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}
