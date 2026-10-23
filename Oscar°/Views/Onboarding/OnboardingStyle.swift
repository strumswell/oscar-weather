//
//  OnboardingStyle.swift
//  Oscar°
//

import SwiftUI

enum OnboardingMetrics {
    static let cornerRadius: CGFloat = 28
    static let edgePadding: CGFloat = 24
    static let contentMaxWidth: CGFloat = 480
    static let tourHeroShare: CGFloat = 0.5

    static let navy = LinearGradient(
        colors: [
            Color(hue: 0.60, saturation: 0.58, brightness: 0.36),
            Color(hue: 0.64, saturation: 0.78, brightness: 0.14),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

struct OnboardingLayout {
    var size = CGSize.zero
    var insets = EdgeInsets()

    var isPad: Bool { size.width >= 700 }

    var cardFrame: CGRect {
        let card = CGSize(width: min(600, size.width - 48), height: min(820, size.height - 48))
        return CGRect(x: (size.width - card.width) / 2, y: (size.height - card.height) / 2, width: card.width, height: card.height)
    }

    var fullBleed: CGRect {
        CGRect(
            x: -insets.leading,
            y: -insets.top,
            width: size.width + insets.leading + insets.trailing,
            height: size.height + insets.top + insets.bottom
        )
    }

    var heroFrame: CGRect {
        let page = isPad ? cardFrame : CGRect(origin: .zero, size: size)
        let top: CGFloat = isPad ? 20 : 12
        return CGRect(x: page.minX + 20, y: page.minY + top, width: page.width - 40, height: page.height * OnboardingMetrics.tourHeroShare - top - 8)
    }
}

extension EnvironmentValues {
    @Entry var onboardingLayout = OnboardingLayout()
}

struct OnboardingPage<Hero: View, Content: View, Buttons: View>: View {
    var heroShare: CGFloat = 0
    @ViewBuilder var hero: Hero
    @ViewBuilder var content: Content
    @ViewBuilder var buttons: Buttons

    @Environment(\.onboardingLayout) private var layout

    var body: some View {
        let card = layout.cardFrame
        stacked
            .frame(width: layout.isPad ? card.width : nil, height: layout.isPad ? card.height : nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stacked: some View {
        VStack(spacing: 0) {
            if heroShare > 0, layout.isPad {
                hero
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .frame(height: layout.cardFrame.height * heroShare)
            } else if heroShare > 0 {
                hero
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .containerRelativeFrame(.vertical) { height, _ in height * heroShare }
            }

            content
                .frame(maxWidth: OnboardingMetrics.contentMaxWidth)
                .padding(.horizontal, OnboardingMetrics.edgePadding)
                .padding(.top, heroShare > 0 ? 28 : 8)

            Spacer(minLength: 16)

            buttons
                .frame(maxWidth: OnboardingMetrics.contentMaxWidth)
                .padding(.horizontal, OnboardingMetrics.edgePadding)
                .padding(.bottom, layout.isPad ? 20 : 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OnboardingHeadline<Footer: View>: View {
    let title: LocalizedStringKey
    let copy: LocalizedStringKey
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.onboardingTitle)
                .fixedSize(horizontal: false, vertical: true)
            Text(copy)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            footer
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

extension OnboardingHeadline where Footer == EmptyView {
    init(title: LocalizedStringKey, copy: LocalizedStringKey) {
        self.init(title: title, copy: copy, footer: { EmptyView() })
    }
}

struct OnboardingSymbol: View {
    let name: String
    let tint: Color
    var appeared = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: name)
            .font(.title.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 72, height: 72)
            .background(tint.gradient, in: Circle())
            .shadow(color: tint.opacity(0.45), radius: 24, y: 8)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(duration: 0.7, bounce: 0.35).delay(0.05), value: appeared)
            .accessibilityHidden(true)
    }
}

extension Font {
    static let onboardingTitle = Font.system(.title, design: .rounded, weight: .bold)
}

extension AnyTransition {
    static func onboardingSlide(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: 60).combined(with: .opacity),
            removal: .offset(x: -60).combined(with: .opacity)
        )
    }
}

struct OnboardingEntranceModifier: ViewModifier {
    let appeared: Bool
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .animation(.spring(duration: 0.7, bounce: 0.2).delay(delay), value: appeared)
    }
}

extension View {
    func onboardingEntrance(_ appeared: Bool, delay: Double) -> some View {
        modifier(OnboardingEntranceModifier(appeared: appeared, delay: delay))
    }

    func catDash() -> some View {
        modifier(CatDashModifier())
    }
}

private struct CatDashModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CatNeeds.enabledKey) private var catEnabled = true
    @State private var width: CGFloat = 0
    @State private var visit: CatVisit?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay(alignment: .top) {
                if let visit {
                    CatVisitSprite(visit: visit)
                }
            }
            .task {
                guard !reduceMotion, catEnabled, !ScreenshotMode.active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Double.random(in: 3...10)))
                    guard !Task.isCancelled, width > 0 else { continue }
                    let next = CatVisit(width: width)
                    visit = next
                    try? await Task.sleep(for: .seconds(next.duration + 0.1))
                    visit = nil
                }
            }
    }
}

private struct CatVisit {
    let start = Date.now
    let width: CGFloat
    let leftToRight = Bool.random()
    let stopX: CGFloat
    let rest: CatAnim
    let restDuration: Double
    let hearts: Bool

    static let speed: CGFloat = 220
    static let size: CGFloat = 32

    init(width: CGFloat) {
        self.width = width
        stopX = width * CGFloat.random(in: 0.25...0.75)
        rest = [.idle, .sit, .sleep].randomElement()!
        restDuration = rest == .sleep ? Double.random(in: 4...7) : Double.random(in: 2.5...5)
        hearts = rest != .sleep && Bool.random()
    }

    var enterDuration: Double { Double((stopX + Self.size) / Self.speed) }
    var duration: Double { enterDuration + restDuration + Double((width - stopX + Self.size) / Self.speed) }

    func pose(at elapsed: Double) -> (anim: CatAnim, animElapsed: Double, x: CGFloat) {
        let anim: CatAnim
        let animElapsed: Double
        let x: CGFloat
        if elapsed < enterDuration {
            anim = .run
            animElapsed = elapsed
            x = -Self.size + Self.speed * CGFloat(elapsed)
        } else if elapsed < enterDuration + restDuration {
            anim = rest
            animElapsed = elapsed - enterDuration
            x = stopX
        } else {
            anim = .run
            animElapsed = elapsed - enterDuration - restDuration
            x = stopX + Self.speed * CGFloat(animElapsed)
        }
        return (anim, animElapsed, leftToRight ? x : width - x)
    }
}

private struct CatVisitSprite: View {
    let visit: CatVisit

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let elapsed = context.date.timeIntervalSince(visit.start)
            let pose = visit.pose(at: elapsed)
            ZStack {
                PixelSprite(
                    sheet: pose.anim.sheet,
                    frames: pose.anim.frames,
                    frame: pose.anim.frame(after: pose.animElapsed),
                    size: CGSize(width: CatVisit.size, height: CatVisit.size),
                    flipped: !visit.leftToRight
                )
                .position(x: pose.x, y: -CatVisit.size / 2 - 2)

                if visit.hearts {
                    let heartAge = elapsed - visit.enterDuration - 0.8
                    ForEach(0..<3, id: \.self) { index in
                        let age = heartAge - Double(index) * 0.2
                        if age > 0, age < 1.2 {
                            Image("cat_heart")
                                .interpolation(.none)
                                .opacity(1 - age / 1.2)
                                .position(x: pose.x + CGFloat(index - 1) * 7, y: -30 - CGFloat(age) * 20)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
