import CoreMotion
import SwiftUI

@MainActor
@Observable
final class MemberCardMotion {
    var tilt: CGSize = .zero
    var glint: Double = -1
    var manualTilt: CGSize?
    var forcesFloat = false

    @ObservationIgnored private var sweepStart: Date?

    func sweep() {
        sweepStart = .now
    }

    func run(reduceMotion: Bool) async {
        guard !reduceMotion else {
            tilt = .zero
            glint = -1
            return
        }
        let motion = CMMotionManager()
        let hasGyro = motion.isDeviceMotionAvailable
        if hasGyro {
            motion.deviceMotionUpdateInterval = 1.0 / 60
            motion.startDeviceMotionUpdates()
        }
        defer { motion.stopDeviceMotionUpdates() }
        let start = Date.now
        var baseline: CGPoint?
        while (try? await Task.sleep(for: .milliseconds(16))) != nil {
            let time = Date.now.timeIntervalSince(start)
            let target: CGSize
            if let manualTilt {
                target = manualTilt
            } else if hasGyro, !forcesFloat, let gravity = motion.deviceMotion?.gravity {
                let now = CGPoint(x: gravity.screenX, y: gravity.screenY)
                var base = baseline ?? now
                base.x += (now.x - base.x) * 0.02
                base.y += (now.y - base.y) * 0.02
                baseline = base
                target = CGSize(width: Self.settled((now.x - base.x) * 2.5), height: Self.settled((now.y - base.y) * 2.5))
            } else if forcesFloat {
                target = CGSize(width: sin(time * .pi * 2 / 10) * 0.14, height: cos(time * .pi * 2 / 13) * 0.08)
            } else {
                target = .zero
            }
            tilt = CGSize(
                width: tilt.width + (target.width - tilt.width) * 0.15,
                height: tilt.height + (target.height - tilt.height) * 0.15
            )
            glint = glintPhase()
        }
    }

    private func glintPhase() -> Double {
        guard let sweepStart else { return -1 }
        let elapsed = Date.now.timeIntervalSince(sweepStart)
        if elapsed < 1.1 { return elapsed / 1.1 }
        self.sweepStart = nil
        return -1
    }

    private static func settled(_ value: Double) -> Double {
        abs(value) < 0.05 ? 0 : min(max(value, -1), 1)
    }
}

@MainActor
@Observable
final class MemberCardShow {
    let motion = MemberCardMotion()
    var flipAngle = 0.0
    var revealFrom: MemberTier?
    var revealAngle = 0.0
    var lift = 0.0
    var slamTrigger = 0
    var stampHidden = false

    var showsBack: Bool { flipAngle >= 90 }

    func flip(reduceMotion: Bool) {
        Haptics.tick()
        let target = showsBack ? 0.0 : 180.0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.75, bounce: 0.32)) {
            flipAngle = target
        }
        if !reduceMotion { motion.sweep() }
    }

    func showFront() {
        guard showsBack else { return }
        withAnimation(.spring(duration: 0.6, bounce: 0.2)) {
            flipAngle = 0
        }
    }

    func playTierUp(from old: MemberTier, reduceMotion: Bool) async {
        if flipAngle != 0 { showFront() }
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.3)) { revealFrom = nil }
            Haptics.success()
            return
        }
        revealAngle = 0
        revealFrom = old
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { lift = 1 }
        try? await Task.sleep(for: .milliseconds(220))
        withAnimation(.spring(duration: 0.95, bounce: 0.38)) { revealAngle = 180 }
        try? await Task.sleep(for: .milliseconds(330))
        Haptics.success()
        try? await Task.sleep(for: .milliseconds(170))
        withAnimation(.spring(duration: 0.5, bounce: 0.3)) { lift = 0 }
        motion.sweep()
        try? await Task.sleep(for: .milliseconds(700))
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            revealFrom = nil
            revealAngle = 0
        }
    }

    func playStamp(reduceMotion: Bool) async {
        if flipAngle != 0 {
            showFront()
            try? await Task.sleep(for: .milliseconds(450))
        }
        stampHidden = false
        guard !reduceMotion else { return }
        slamTrigger += 1
        try? await Task.sleep(for: .milliseconds(Int(MemberCardStampSlam.impact * 1000)))
        Haptics.stamp()
    }
}

@Animatable
struct MemberCardFlip<Front: View, Back: View>: View {
    var angle: Double
    @AnimatableIgnored var perspective: CGFloat
    @AnimatableIgnored var front: Front
    @AnimatableIgnored var back: Back

    init(angle: Double, perspective: CGFloat = 0.5, @ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back) {
        self.angle = angle
        self.perspective = perspective
        self.front = front()
        self.back = back()
    }

    var body: some View {
        let showsBack = angle >= 90
        ZStack(alignment: .top) {
            front
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: perspective)
                .opacity(showsBack ? 0 : 1)
                .allowsHitTesting(!showsBack)
                .accessibilityHidden(showsBack)
            back
                .rotation3DEffect(.degrees(angle - 180), axis: (x: 0, y: 1, z: 0), perspective: perspective)
                .opacity(showsBack ? 1 : 0)
                .allowsHitTesting(showsBack)
                .accessibilityHidden(!showsBack)
        }
    }
}

struct MemberCardTiltEffect: ViewModifier {
    let motion: MemberCardMotion
    let isActive: Bool

    func body(content: Content) -> some View {
        let tilt = isActive ? motion.tilt : .zero
        let x = -tilt.height * 3.5
        let y = tilt.width * 4.5
        content
            .rotation3DEffect(.degrees((x * x + y * y).squareRoot()), axis: (x: x, y: y, z: 0), perspective: 0.4)
    }
}

struct MemberCardShadow: ViewModifier {
    let motion: MemberCardMotion
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let tilt = motion.tilt
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.black)
                    .padding(8)
                    .shadow(color: .black.opacity(0.55), radius: 20, x: -tilt.width * 10, y: 16 - tilt.height * 8)
            }
    }
}
