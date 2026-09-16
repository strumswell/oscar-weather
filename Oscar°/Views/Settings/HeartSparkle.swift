import SwiftUI

/// A glint that pops over the support heart every few seconds.
struct HeartSparkle: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    if !reduceMotion {
      Image(systemName: "sparkle")
        .font(.system(size: 9, weight: .bold))
        .accessibilityHidden(true)
        .keyframeAnimator(initialValue: 0.0) { content, glint in
          content
            .scaleEffect(glint)
            .rotationEffect(.degrees(glint * 90))
            .opacity(glint)
        } keyframes: { _ in
          KeyframeTrack {
            LinearKeyframe(0, duration: 3.5)
            SpringKeyframe(1, duration: 0.35, spring: .bouncy)
            CubicKeyframe(0, duration: 0.45)
          }
        }
    }
  }
}
