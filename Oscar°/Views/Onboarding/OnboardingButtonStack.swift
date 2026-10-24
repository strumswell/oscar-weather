//
//  OnboardingButtonStack.swift
//  Oscar°
//

import SwiftUI

struct OnboardingButtonStack: View {
    let primaryTitle: LocalizedStringKey
    var primaryDisabled = false
    let primaryAction: () -> Void
    var secondaryTitle: LocalizedStringKey? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Button(action: primaryAction) {
                Text(primaryTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .disabled(primaryDisabled)
            .buttonCat()

            if let secondaryTitle, let secondaryAction {
                Button(action: secondaryAction) {
                    Text(secondaryTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
    }
}
