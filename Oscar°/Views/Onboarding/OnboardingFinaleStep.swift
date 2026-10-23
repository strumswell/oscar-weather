//
//  OnboardingFinaleStep.swift
//  Oscar°
//

import SwiftUI

struct OnboardingFinaleStep: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var showsSubtitle = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            OnboardingLockup()
                .blur(radius: appeared || reduceMotion ? 0 : 12)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.8)
                .opacity(appeared ? 1 : 0)

            Text("Alles bereit.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 12)
                .opacity(showsSubtitle ? 1 : 0)

            Spacer()

            OnboardingButtonStack(primaryTitle: "Zum Wetter", primaryAction: onFinish)
                .padding(.horizontal, OnboardingMetrics.edgePadding)
                .frame(maxWidth: OnboardingMetrics.contentMaxWidth)
                .padding(.bottom, 6)
                .opacity(showsSubtitle ? 1 : 0)
        }
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.3).delay(0.35)) {
                appeared = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.8)) {
                showsSubtitle = true
            }
        }
    }
}

#Preview {
    ZStack {
        Color.blue.ignoresSafeArea()
        Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
        OnboardingFinaleStep {}
    }
    .preferredColorScheme(.dark)
}
