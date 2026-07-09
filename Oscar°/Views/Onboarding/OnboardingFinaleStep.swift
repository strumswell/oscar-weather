//
//  OnboardingFinaleStep.swift
//  Oscar°
//

import SwiftUI

/// Last screen: the welcome greeting returns as a bookend over the frosted
/// NowView that is already living underneath — the final button just lets
/// the glass dissolve.
struct OnboardingFinaleStep: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var showsSubtitle = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.yellow.gradient)
                .symbolEffect(.bounce, options: .repeat(.periodic(delay: 2.5)))
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text("Willkommen bei")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(verbatim: "Oscar°")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
            }
            .padding(.top, 18)
            .blur(radius: appeared || reduceMotion ? 0 : 12)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.8)
            .opacity(appeared ? 1 : 0)

            Text("Deine Vorhersage ist bereit.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .opacity(showsSubtitle ? 1 : 0)

            Spacer()

            OnboardingButtonStack(primaryTitle: "Zur Vorhersage", primaryAction: onFinish)
                .opacity(showsSubtitle ? 1 : 0)
        }
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.3).delay(0.25)) {
                appeared = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.7)) {
                showsSubtitle = true
            }
        }
    }
}

#Preview {
    OnboardingFinaleStep {}
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
}
