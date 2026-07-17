//
//  CardBackground.swift
//  Oscar°
//

import SwiftUI

extension EnvironmentValues {
    /// Base of the forecast/AQI cards: the frosted material everywhere in the
    /// app; the onboarding collage overrides it with a cheap flat fill so
    /// dozens of moving copies don't each re-blur the animated sky.
    @Entry var cardBackgroundStyle = AnyShapeStyle(.thinMaterial)

    /// Sky-adaptive wash laid over the card base (AtmosphereSampler.cardFill).
    /// Injected by the Now stack so cards share the scene's hue while keeping
    /// the material's frosted look; nil elsewhere (sheets, onboarding).
    @Entry var cardTint: Color? = nil
}

private struct CardBackgroundModifier: ViewModifier {
    @Environment(\.cardBackgroundStyle) private var style
    @Environment(\.cardTint) private var tint

    func body(content: Content) -> some View {
        if let tint {
            content.background(tint).background(style)
        } else {
            content.background(style)
        }
    }
}

private struct CardShapeBackgroundModifier<S: Shape>: ViewModifier {
    @Environment(\.cardBackgroundStyle) private var style
    @Environment(\.cardTint) private var tint
    let shape: S

    func body(content: Content) -> some View {
        if let tint {
            content.background(tint, in: shape).background(style, in: shape)
        } else {
            content.background(style, in: shape)
        }
    }
}

extension View {
    /// The environment card fill as background (pair with clipShape).
    func cardBackground() -> some View {
        modifier(CardBackgroundModifier())
    }

    /// The environment card fill clipped to a shape.
    func cardBackground(in shape: some Shape) -> some View {
        modifier(CardShapeBackgroundModifier(shape: shape))
    }

    /// The hairline that lifts a card off the sim: semi-transparent white,
    /// shared by every card.
    func cardBorder(_ shape: some InsettableShape) -> some View {
        overlay(shape.strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }

    func cardBorder() -> some View {
        cardBorder(RoundedRectangle(cornerRadius: 10))
    }
}
