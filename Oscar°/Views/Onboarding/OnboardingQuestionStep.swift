//
//  OnboardingQuestionStep.swift
//  Oscar°
//

import SwiftUI

struct OnboardingQuestionStep<Footer: View>: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let copy: LocalizedStringKey
    let primaryTitle: LocalizedStringKey
    let primaryAction: () -> Void
    let secondaryTitle: LocalizedStringKey
    let secondaryAction: () -> Void
    @ViewBuilder var footer: Footer

    @State private var appeared = false

    var body: some View {
        OnboardingPage(heroShare: 0.4) {
            OnboardingSymbol(name: symbol, tint: tint, appeared: appeared)
        } content: {
            OnboardingHeadline(title: title, copy: copy) { footer }
                .onboardingEntrance(appeared, delay: 0.15)
        } buttons: {
            OnboardingButtonStack(
                primaryTitle: primaryTitle,
                primaryAction: primaryAction,
                secondaryTitle: secondaryTitle,
                secondaryAction: secondaryAction
            )
            .onboardingEntrance(appeared, delay: 0.3)
        }
        .onAppear { appeared = true }
    }
}
