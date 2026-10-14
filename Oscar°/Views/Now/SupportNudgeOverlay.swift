import CoreMotion
import SwiftUI

/// Oscar drops in on a rope, peeks in from the trailing edge or surfaces
/// from below the screen and asks for support; a tap opens the support
/// sheet. Leaving without a purchase, by "Nicht jetzt", by ignoring it or by
/// switching away, counts as a dismissal and pushes the next ask back.
struct SupportNudgeOverlay: View {
    let isEnabled: Bool

    @Environment(NowPresentationCoordinator.self) private var presentation
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SupportNudge.forcedKey) private var isForced = false
    @State private var pose: SupportNudge.Pose?
    @State private var insets = EdgeInsets()
    @State private var isOut = false
    @State private var isTalking = false
    @State private var isAsking = false
    @State private var isTrial = false
    /// Bumped after every exit so the rules run again; with `-supportNudge`
    /// that brings the next cat.
    @State private var round = 0

    private static let delay = Duration.seconds(7)
    private static let patience = Duration.seconds(15)

    /// The rappelling cat's head: beside the place name, or below the top
    /// bars where they reach further down. The rope swings from the screen top.
    private static let rappelMinTop = 90.0
    private static let rappelGap = 28.0
    /// The rope's leading edge inside `nudge_rappel`, in points.
    private static let ropeX = 83.2
    private static let ropeWidth = 5.0
    private static let rappelSize = CGSize(width: 111.7, height: 142)
    /// The peek image ends in a straight cut at 989 of its 1055 px width;
    /// that cut sits far enough past the screen edge that the entrance
    /// spring's overshoot never pulls it on screen.
    private static let peekHeight = 180.0
    private static let peekOverhang = peekHeight * 1055 / 1432 * (1055 - 989) / 1055 + 16
    private static let diverHeight = 160.0
    /// Behind a bottom tab bar the glass covers the diver's fade; without
    /// one (iPad, Mac) it rises from the screen edge.
    private static let diverBarLift = 40.0
    private static let diverSink = 8.0
    private static let bottomBarMinInset = 50.0

    private var rappelTop: CGFloat { max(insets.top + Self.rappelGap, Self.rappelMinTop) }

    private var isBehindBar: Bool { insets.bottom > Self.bottomBarMinInset }

    private var diverLift: CGFloat { isBehindBar ? Self.diverBarLift : -Self.diverSink }

    private var canShow: Bool {
        isEnabled
            && scenePhase == .active
            && presentation.selectedTab == .forecast
            && presentation.sheet == nil
            && !OnboardingCoordinator.shared.isPresented
    }

    var body: some View {
        Color.clear
            .overlay {
                if let pose {
                    figure(pose)
                }
            }
            .ignoresSafeArea()
            .onGeometryChange(for: EdgeInsets.self, of: { $0.safeAreaInsets }) { insets = $0 }
            .task(id: canShow ? round : -1) { await run() }
            .onChange(of: pose) { _, pose in presentation.isNudgeOut = pose != nil }
            .onChange(of: isForced, restart)
            .onChange(of: presentation.requestedNudge) { _, requested in
                if requested != nil { restart() }
            }
            .onChange(of: canShow) { _, can in
                if !can, !isAsking { leave(dismissed: true) }
            }
    }

    private func run() async {
        guard canShow else { return }
        if isAsking {
            // Back from the sheet: bought something or said not now.
            isAsking = false
            leave(dismissed: !SupporterStore.shared.isSupporter)
            return
        }
        let requested = presentation.requestedNudge
        guard pose == nil, requested != nil || SupportNudge.isDue else { return }
        if requested == nil {
            guard (try? await Task.sleep(for: Self.delay)) != nil else { return }
        }
        presentation.requestedNudge = nil
        isTrial = requested != nil
        // Forced runs record no dismissals, so they cycle by round.
        pose = requested ?? (isForced ? SupportNudge.Pose.allCases[round % 3] : SupportNudge.pose)
        guard (try? await Task.sleep(for: Self.patience)) != nil else { return }
        leave(dismissed: true)
    }

    private func restart() {
        if pose == nil { round += 1 } else { leave(dismissed: false) }
    }

    private func enter() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.4) : .spring(duration: 0.9, bounce: 0.3)) {
            isOut = true
        } completion: {
            guard isOut else { return }
            withAnimation(.spring(duration: 0.4, bounce: 0.35)) { isTalking = true }
        }
    }

    private func leave(dismissed: Bool) {
        guard pose != nil else { return }
        // Already on its way out, or not in yet.
        guard isOut else {
            pose = nil
            return
        }
        if dismissed, !isTrial { SupportNudge.recordDismissal() }
        withAnimation(.easeOut(duration: 0.15)) { isTalking = false }
        withAnimation(.easeIn(duration: reduceMotion ? 0.3 : 0.45)) {
            isOut = false
        } completion: {
            pose = nil
            isTalking = false
            round += 1
        }
    }

    private func ask() {
        isAsking = true
        presentation.present(.support)
    }

    private func figure(_ pose: SupportNudge.Pose) -> some View {
        Button(action: ask) {
            HStack(alignment: .top, spacing: 2) {
                SupportNudgeBubble()
                    // Lines the bubble up with the cat's face.
                    .padding(.top, pose == .rappel ? 50 : 40)
                    .scaleEffect(isTalking ? 1 : 0.4, anchor: .trailing)
                    .opacity(isTalking ? 1 : 0)
                cat(pose)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(SupportNudge.line))
        .offset(isOut || reduceMotion ? .zero : hiddenOffset(pose))
        .opacity(isOut || !reduceMotion ? 1 : 0)
        .padding(.top, pose == .rappel ? rappelTop : 0)
        .padding(.trailing, trailing(pose))
        .padding(.bottom, pose == .diver ? diverLift : 0)
        .offset(y: pose == .peek ? 60 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(pose))
        .onAppear(perform: enter)
    }

    @ViewBuilder
    private func cat(_ pose: SupportNudge.Pose) -> some View {
        let phases = reduceMotion ? [0.0] : [-1.0, 1.0]
        switch pose {
        case .rappel:
            // Swings from the rope's top end at the screen edge.
            let pivot = UnitPoint(
                x: (Self.ropeX + Self.ropeWidth / 2) / Self.rappelSize.width,
                y: -rappelTop / Self.rappelSize.height
            )
            Image(decorative: pose.imageName)
                .background(alignment: .topLeading) {
                    Image(decorative: "nudge_rope")
                        .resizable(resizingMode: .tile)
                        .frame(width: Self.ropeWidth, height: 1200)
                        .offset(x: Self.ropeX, y: -1200)
                }
                .phaseAnimator(phases) { content, phase in
                    content.rotationEffect(.degrees(phase * 2.5), anchor: pivot)
                } animation: { _ in .easeInOut(duration: 1.8) }
                .modifier(GravityTilt(anchor: pivot, isActive: !reduceMotion))
        case .peek:
            Image(decorative: pose.imageName)
                .resizable()
                .scaledToFit()
                .frame(height: Self.peekHeight)
                // Leans back towards the edge only, so the cut never shows.
                .phaseAnimator(phases) { content, phase in
                    content.offset(x: (phase + 1) * 4)
                } animation: { _ in .easeInOut(duration: 1.4) }
        case .diver:
            Image(decorative: pose.imageName)
                .resizable()
                .scaledToFit()
                .frame(height: Self.diverHeight)
                .mask {
                    LinearGradient(
                        stops: [.init(color: .black, location: isBehindBar ? 0.7 : 1), .init(color: .clear, location: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .phaseAnimator(phases) { content, phase in
                    content
                        .offset(y: phase * 5)
                        .rotationEffect(.degrees(phase * -2), anchor: .bottom)
                } animation: { _ in .easeInOut(duration: 1.2) }
        }
    }

    private func alignment(_ pose: SupportNudge.Pose) -> Alignment {
        switch pose {
        case .rappel: .topTrailing
        case .peek: .trailing
        case .diver: .bottomTrailing
        }
    }

    private func trailing(_ pose: SupportNudge.Pose) -> CGFloat {
        switch pose {
        case .rappel: 8
        case .peek: -Self.peekOverhang
        // Inside the floating tab bar's width, so the glass covers the fade.
        case .diver: 72
        }
    }

    private func hiddenOffset(_ pose: SupportNudge.Pose) -> CGSize {
        switch pose {
        case .rappel: CGSize(width: 0, height: -(rappelTop + Self.rappelSize.height + 60))
        case .peek: CGSize(width: 180, height: 0)
        case .diver: CGSize(width: 0, height: Self.diverHeight + diverLift + 20)
        }
    }
}

/// Leans the rope a little towards real down when the device tilts.
private struct GravityTilt: ViewModifier {
    let anchor: UnitPoint
    let isActive: Bool

    @State private var degrees = 0.0

    private static let gain = 30.0
    private static let maxDegrees = 20.0
    private static let smoothing = 0.1

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(degrees), anchor: anchor)
            .task(id: isActive) {
                guard isActive else { return }
                let motion = CMMotionManager()
                guard motion.isDeviceMotionAvailable else { return }
                motion.deviceMotionUpdateInterval = 1.0 / 60
                motion.startDeviceMotionUpdates()
                defer { motion.stopDeviceMotionUpdates() }
                while (try? await Task.sleep(for: .milliseconds(16))) != nil {
                    guard let gravity = motion.deviceMotion?.gravity else { continue }
                    let target = min(max(-screenX(gravity) * Self.gain, -Self.maxDegrees), Self.maxDegrees)
                    degrees += (target - degrees) * Self.smoothing
                }
            }
    }

    /// Gravity's pull along the screen's horizontal axis.
    private func screenX(_ gravity: CMAcceleration) -> Double {
        let scene = UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene
        return switch scene?.effectiveGeometry.interfaceOrientation ?? .portrait {
        case .portraitUpsideDown: -gravity.x
        case .landscapeLeft: gravity.y
        case .landscapeRight: -gravity.y
        default: gravity.x
        }
    }
}

/// Solid plate over the animated sky, inked like the cat's outlines.
private struct SupportNudgeBubble: View {
    private static let ink = Color(red: 0.11, green: 0.13, blue: 0.2)

    var body: some View {
        Text(SupportNudge.line)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Self.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 10)
            .padding(.leading, 14)
            .padding(.trailing, 14 + BubbleShape.tail)
            .background {
                BubbleShape()
                    .fill(.white)
                    .stroke(Self.ink, lineWidth: 2)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            }
            .frame(maxWidth: 180, alignment: .trailing)
    }
}

/// Rounded plate with a tail on the trailing side, pointing at the cat.
private struct BubbleShape: Shape {
    static let tail = 10.0

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width - Self.tail, height: rect.height)
        let y = min(body.midY, body.minY + 22)
        var tail = Path()
        tail.move(to: CGPoint(x: body.maxX - 4, y: y - 7))
        tail.addLine(to: CGPoint(x: rect.maxX, y: y + 3))
        tail.addLine(to: CGPoint(x: body.maxX - 4, y: y + 7))
        tail.closeSubpath()
        return Path(roundedRect: body, cornerRadius: 16).union(tail)
    }
}
