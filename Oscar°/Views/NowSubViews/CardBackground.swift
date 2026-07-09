//
//  CardBackground.swift
//  Oscar°
//

import SwiftUI

extension EnvironmentValues {
    /// Background style of the small forecast/AQI cards: live material in the
    /// app, overridden with a cheap translucent fill where dozens of moving
    /// copies would each re-blur the animated sky every frame (the onboarding
    /// collage).
    @Entry var cardBackgroundStyle = AnyShapeStyle(.thinMaterial)
}
