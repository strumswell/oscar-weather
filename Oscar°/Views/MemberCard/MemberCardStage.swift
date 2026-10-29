import SwiftUI

struct MemberCardStage<Front: View, Back: View>: View {
    let show: MemberCardShow
    let tier: MemberTier
    let width: CGFloat
    let tiltActive: Bool
    @ViewBuilder let front: (MemberTier) -> Front
    @ViewBuilder let back: () -> Back

    var body: some View {
        let radius = MemberCardPalette.cornerRadius(for: width)
        MemberCardFlip(angle: show.flipAngle) {
            frontSide(radius: radius)
        } back: {
            back()
                .modifier(MemberCardShadow(motion: show.motion, cornerRadius: radius))
        }
        .modifier(MemberCardTiltEffect(motion: show.motion, isActive: tiltActive))
        .scaleEffect(1 + show.lift * 0.045)
        .offset(y: -show.lift * 14)
        .keyframeAnimator(initialValue: 0.0, trigger: show.slamTrigger) { content, dip in
            content
                .offset(y: dip * 6)
                .scaleEffect(1 - dip * 0.018)
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(0)
                LinearKeyframe(0, duration: MemberCardStampSlam.impact)
                CubicKeyframe(1, duration: 0.05)
                SpringKeyframe(-0.3, duration: 0.14)
                SpringKeyframe(0, duration: 0.35)
            }
        }
    }

    @ViewBuilder
    private func frontSide(radius: CGFloat) -> some View {
        if let old = show.revealFrom {
            MemberCardFlip(angle: show.revealAngle) {
                front(old)
                    .modifier(MemberCardShadow(motion: show.motion, cornerRadius: radius))
            } back: {
                front(tier)
                    .modifier(MemberCardShadow(motion: show.motion, cornerRadius: radius))
            }
        } else {
            front(tier)
                .modifier(MemberCardShadow(motion: show.motion, cornerRadius: radius))
        }
    }
}
