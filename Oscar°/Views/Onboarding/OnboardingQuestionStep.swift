//
//  OnboardingQuestionStep.swift
//  Oscar°
//

import SwiftUI

struct OnboardingQuestionStep<Footer: View>: View {
    let icon: OnboardingStepIcon
    let title: LocalizedStringKey
    let copy: LocalizedStringKey
    let primaryTitle: LocalizedStringKey
    let primaryAction: () -> Void
    let secondaryTitle: LocalizedStringKey
    let secondaryAction: () -> Void
    @ViewBuilder var footer: Footer

    @State private var appeared = false

    var body: some View {
        OnboardingStageLayout(layout: .question) {
            VStack(spacing: 0) {
                ScrollView {
                    OnboardingHeadline(icon: icon, title: title, copy: copy) { footer }
                        .padding(.horizontal, OnboardingStage.edgePadding)
                        .padding(.top, OnboardingStage.canvasInset)
                        .onboardingEntrance(appeared, delay: 0.1)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)

                OnboardingButtonStack(
                    primaryTitle: primaryTitle,
                    primaryAction: primaryAction,
                    secondaryTitle: secondaryTitle,
                    secondaryAction: secondaryAction
                )
                .onboardingEntrance(appeared, delay: 0.3)
            }
        }
        .onAppear { appeared = true }
    }
}
