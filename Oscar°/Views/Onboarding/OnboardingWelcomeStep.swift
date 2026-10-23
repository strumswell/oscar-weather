//
//  OnboardingWelcomeStep.swift
//  Oscar°
//

import SwiftUI

struct OnboardingWelcomeStep: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showsLockup = false
    @State private var showsLetter = false
    @State private var letterFloating = false
    @State private var letterLifting = false
    @State private var letterFlownAway = false

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 900
            let letterWidth = min(proxy.size.width * 0.97, sizeClass == .regular ? 640 : 460)

            VStack(spacing: 0) {
                OnboardingLockup(compact: compact)
                    .padding(.top, compact ? 12 : 32)
                    .scaleEffect(showsLockup || reduceMotion ? 1 : 0.85)
                    .opacity(showsLockup ? 1 : 0)

                letter(maxWidth: letterWidth)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)

                OnboardingButtonStack(primaryTitle: "Los geht's", primaryAction: continueTapped)
                    .padding(.horizontal, OnboardingMetrics.edgePadding)
                    .frame(maxWidth: OnboardingMetrics.contentMaxWidth)
                    .padding(.bottom, 6)
                    .opacity(showsLockup ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: letterFlownAway)
        .onAppear(perform: animateIn)
    }

    private var letterAssetName: String {
        Bundle.main.preferredLocalizations.first == "de" ? "letterDE" : "letterEN"
    }

    private func letter(maxWidth: CGFloat) -> some View {
        Image(letterAssetName)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maxWidth, maxHeight: .infinity)
            .layoutPriority(1)
            .rotationEffect(.degrees(letterFloating ? -1.2 : 1.2))
            .offset(y: letterFloating ? -1 : 0)
            .rotationEffect(.degrees(gustRotation))
            .offset(gustOffset)
            .shadow(color: .black.opacity(0.28), radius: 22, y: 16)
            .blur(radius: letterFlownAway ? 5 : 0)
            .scaleEffect(gustScale)
            .catDash()
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
            }
            withAnimation(.easeOut(duration: 0.35).delay(0.1)) {
                showsLockup = false
            } completion: {
                onContinue()
            }
        }
    }
}

struct OnboardingLockup: View {
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 14 : 22) {
            Image("AppIconOriginalPreview")
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 80 : 104, height: compact ? 80 : 104)
                .clipShape(.rect(cornerRadius: compact ? 18 : 23))
                .shadow(color: .black.opacity(0.3), radius: 18, y: 10)

            VStack(spacing: 2) {
                Text("Willkommen bei")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.92))
                Text(verbatim: "Oscar°")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold).scaled(by: compact ? 1.05 : 1.3))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        Color.blue.ignoresSafeArea()
        Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
        OnboardingWelcomeStep {}
    }
    .preferredColorScheme(.dark)
}
