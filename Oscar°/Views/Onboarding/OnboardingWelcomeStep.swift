//
//  OnboardingWelcomeStep.swift
//  Oscar°
//

import SwiftUI

/// First screen: app icon and greeting over the postcard sky, with the letter
/// that blows away in the wind when the journey starts.
struct OnboardingWelcomeStep: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsIcon = false
    @State private var showsTitle = false
    @State private var showsLetter = false
    @State private var letterFloating = false
    @State private var letterLifting = false
    @State private var letterFlownAway = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)

            Image("AppIconOriginalPreview")
                .resizable()
                .scaledToFit()
                .frame(width: 108, height: 108)
                .clipShape(.rect(cornerRadius: 24))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
                .scaleEffect(showsIcon || reduceMotion ? 1 : 0.6)
                .opacity(showsIcon ? 1 : 0)
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text("Willkommen bei")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                Text(verbatim: "Oscar°")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .padding(.top, 24)
            .opacity(showsTitle ? 1 : 0)
            .offset(y: showsTitle || reduceMotion ? 0 : 14)

            Spacer(minLength: 24)

            // Layout placeholder: the postcard renders as an overlay so its
            // oversized frame can't widen the VStack (which pushed the button
            // to the screen edge) — it overflows the slot in every direction.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { letter.offset(y: -12) }
                .allowsHitTesting(false)

            Spacer(minLength: 28)

            OnboardingButtonStack(primaryTitle: "Los geht's", primaryAction: continueTapped)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: letterFlownAway)
        .onAppear(perform: animateIn)
    }

    /// The handwritten note exists in German and English; every non-German
    /// localization (including Turkish) reads the English one.
    private var letterAssetName: String {
        Bundle.main.preferredLocalizations.first == "de" ? "letterDE" : "letterEN"
    }

    private var letter: some View {
        Image(letterAssetName)
            .resizable()
            .scaledToFit()
            // Note-pad size: the handwriting on it must be legible. The note
            // artwork fills its canvas edge to edge (unlike the old letter),
            // so it renders a touch narrower than the screen and still runs
            // down under the glass button; capped so iPad doesn't get a
            // wall-sized note.
            .containerRelativeFrame(.horizontal) { length, _ in min(length * 0.95, 430) }
            // Ideal height for that width — without this, scaledToFit capped
            // the image at the slot's leftover height and it never grew.
            .fixedSize(horizontal: false, vertical: true)
            // Inner pair: gentle idle float. Outer pair: the wind gust —
            // separate properties, so the two animations never fight.
            .rotationEffect(.degrees(letterFloating ? -1.2 : 1.2))
            .offset(y: letterFloating ? -1 : 0)
            .rotationEffect(.degrees(gustRotation))
            .offset(gustOffset)
            .shadow(color: .black.opacity(0.28), radius: 22, y: 16)
            .blur(radius: letterFlownAway ? 5 : 0)
            .scaleEffect(gustScale)
            .opacity(showsLetter ? 1 : 0)
            // VoiceOver reads the handwriting; the localized value tracks the
            // same language split as the artwork itself.
            .accessibilityLabel(Text("Danke, dass Du Oscar ausprobierst. Viele Jahre und viel Herzblut sind hier reingeflossen. Ich hoffe, es gefällt Dir mindestens so viel wie mir! - Philipp. Für Oscar, Daniela, Ursel, Werner, Reinhard & Sammy"))
    }

    private func animateIn() {
        if reduceMotion {
            withAnimation(.easeIn(duration: 0.4)) {
                showsIcon = true
                showsTitle = true
                showsLetter = true
            }
            return
        }

        withAnimation(.spring(duration: 0.7, bounce: 0.35).delay(0.15)) { showsIcon = true }
        withAnimation(.easeOut(duration: 0.6).delay(0.45)) { showsTitle = true }
        withAnimation(.spring(duration: 0.8, bounce: 0.25).delay(0.75)) { showsLetter = true }
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

    /// The wind takes the letter in two beats: a short lift as the gust
    /// catches it, then the rush off to the upper left.
    private func continueTapped() {
        guard !letterLifting, !letterFlownAway else { return }

        if reduceMotion {
            onContinue()
            return
        }

        // Quick and sequential: overlapping the fly-away with the step slide
        // stacked two full-screen blur transitions in one beat and dropped
        // frames — so the note rushes off fast, then the standard slide runs.
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
