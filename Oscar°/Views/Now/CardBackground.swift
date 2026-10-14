//
//  CardBackground.swift
//  Oscar°
//

import SwiftUI

extension EnvironmentValues {
    @Entry var cardBackgroundStyle = AnyShapeStyle(.thinMaterial)

    @Entry var cardTint: Color? = nil

    @Entry var cardBorderOpacity: Double = 0.15
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

private struct CardBorderModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.cardBorderOpacity) private var opacity
    let shape: S

    func body(content: Content) -> some View {
        content.overlay(shape.strokeBorder(.white.opacity(opacity), lineWidth: 1))
    }
}

extension View {
    func cardBackground() -> some View {
        modifier(CardBackgroundModifier())
    }

    func cardBackground(in shape: some Shape) -> some View {
        modifier(CardShapeBackgroundModifier(shape: shape))
    }

    func cardBorder(_ shape: some InsettableShape) -> some View {
        modifier(CardBorderModifier(shape: shape))
    }

    func cardBorder() -> some View {
        cardBorder(RoundedRectangle(cornerRadius: 10))
    }
}
