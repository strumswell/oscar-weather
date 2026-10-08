//
//  OnboardingFinaleStep.swift
//  Oscar°
//

import SwiftUI

/// Last screen: the welcome greeting returns as a bookend over the frosted
/// NowView that is already living underneath. The final button just lets
/// the glass dissolve.
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
                .foregroundStyle(.secondary)
                .padding(.top, 12)
                .opacity(showsSubtitle ? 1 : 0)

            Spacer()

            OnboardingButtonStack(primaryTitle: "Zum Wetter", primaryAction: onFinish)
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

/// App icon over "Willkommen bei Oscar°": opens the flow on the sky and
/// closes it on the frosted app. `onSky` paints it white with a shadow.
struct OnboardingLockup: View {
    var onSky = false

    var body: some View {
        VStack(spacing: 24) {
            Image("AppIconOriginalPreview")
                .resizable()
                .scaledToFit()
                .frame(width: 108, height: 108)
                .clipShape(.rect(cornerRadius: 24))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)

            VStack(spacing: 2) {
                Text("Willkommen bei")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(onSky ? AnyShapeStyle(.white.opacity(0.92)) : AnyShapeStyle(.secondary))
                Text(verbatim: "Oscar°")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(onSky ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            }
            .shadow(color: .black.opacity(onSky ? 0.18 : 0), radius: 10, y: 4)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OnboardingFinaleStep {}
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
}
