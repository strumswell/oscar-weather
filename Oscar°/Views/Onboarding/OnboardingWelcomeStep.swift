//
//  OnboardingWelcomeStep.swift
//  Oscar°
//

import SwiftUI

struct OnboardingWelcomeStep: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsLockup = false
    @State private var showsLetter = false
    @State private var letterFloating = false
    @State private var letterLifting = false
    @State private var letterFlownAway = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)

            OnboardingLockup(onSky: true)
                .scaleEffect(showsLockup || reduceMotion ? 1 : 0.8)
                .opacity(showsLockup ? 1 : 0)

            Spacer(minLength: 24)

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { letter.offset(y: -12) }
                .allowsHitTesting(false)

            Spacer(minLength: 28)

            OnboardingButtonStack(primaryTitle: "Los geht's", primaryAction: continueTapped)
        }
        .frame(maxHeight: 880)
        .sensoryFeedback(.impact(weight: .medium), trigger: letterFlownAway)
        .onAppear(perform: animateIn)
    }

    private var letterAssetName: String {
        Bundle.main.preferredLocalizations.first == "de" ? "letterDE" : "letterEN"
    }

    private var letter: some View {
        Image(letterAssetName)
            .resizable()
            .scaledToFit()
            .containerRelativeFrame(.horizontal) { length, _ in min(length * 0.95, 430) }
            .fixedSize(horizontal: false, vertical: true)
            .rotationEffect(.degrees(letterFloating ? -1.2 : 1.2))
            .offset(y: letterFloating ? -1 : 0)
            .rotationEffect(.degrees(gustRotation))
            .offset(gustOffset)
            .shadow(color: .black.opacity(0.28), radius: 22, y: 16)
            .blur(radius: letterFlownAway ? 5 : 0)
            .scaleEffect(gustScale)
            .opacity(showsLetter ? 1 : 0)
            .accessibilityLabel(Text("Danke, dass Du Oscar ausprobierst. Viele Jahre und viel Herzblut sind hier reingeflossen. Ich hoffe, es gefällt Dir mindestens so viel wie mir! - Philipp. Für Oscar, Daniela, Ursel, Werner, Reinhard & Sammy"))
    }

    private func animateIn() {
        if reduceMotion {
            withAnimation(.easeIn(duration: 0.4)) {
                showsLockup = true
                showsLetter = true
            }
            return
        }

        withAnimation(.spring(duration: 0.7, bounce: 0.3).delay(0.15)) { showsLockup = true }
        withAnimation(.spring(duration: 0.8, bounce: 0.25).delay(0.65)) { showsLetter = true }
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true).delay(1.6)) {
            letterFloating = true
        }
    }

    private var gustRotation: Double {
        if letterFlownAway { return -34 }
        if letterLifting { return -7 }
        return -4
    }

    private var gustOffset: CGSize {
        if letterFlownAway { return CGSize(width: -560, height: -230) }
        if letterLifting { return CGSize(width: 10, height: -14) }
        return .zero
    }

    private var gustScale: CGFloat {
        if !showsLetter && !reduceMotion { return 0.85 }
        if letterFlownAway { return 1.06 }
        if letterLifting { return 1.02 }
        return 1
    }

    private func continueTapped() {
        guard !letterLifting, !letterFlownAway else { return }

        if reduceMotion {
            onContinue()
            return
        }

        withAnimation(.easeOut(duration: 0.12)) {
            letterLifting = true
        } completion: {
            withAnimation(.easeIn(duration: 0.3)) {
                letterFlownAway = true
            } completion: {
                onContinue()
            }
        }
    }
}

#Preview {
    ZStack {
        OnboardingSceneView(scene: .day)
        OnboardingWelcomeStep {}
    }
    .environment(Weather.mock)
}
