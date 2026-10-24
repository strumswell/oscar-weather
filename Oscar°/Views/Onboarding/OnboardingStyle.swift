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

    func buttonCat() -> some View {
        modifier(ButtonCatModifier())
    }
}

private struct ButtonCatModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CatNeeds.enabledKey) private var catEnabled = true
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay(alignment: .top) {
                if !reduceMotion, catEnabled, !ScreenshotMode.active, width > 0 {
                    ButtonCatSprite(width: width)
                }
            }
    }
}

@MainActor
@Observable
private final class ButtonCat {
    static let shared = ButtonCat()

    var anim = CatAnim.sleep
    var animStart = Date.now
    var glide = Glide.rest(0.7)
    var facesLeft = true
    var burst: CatBurst?
    var nameShownAt: Date?
    var width: CGFloat = 300
    private var busyUntil = Date.now.addingTimeInterval(.random(in: 4...8))

    static let size: CGFloat = 32
    static let margin: CGFloat = 34
    static let nameWidth: CGFloat = 72
    static let nameDuration: TimeInterval = 2.2
    private static let speed: CGFloat = 40

    func x(at date: Date) -> CGFloat {
        Self.margin + glide.x(at: date) * max(width - Self.margin * 2, 0)
    }

    func run() async {
        while !Task.isCancelled {
            think()
            try? await Task.sleep(for: .seconds(min(max(busyUntil.timeIntervalSinceNow, 0.05), 0.5)))
        }
    }

    func tap() {
        let now = Date.now
        glide = .rest(glide.x(at: now))
        nameShownAt = now
        if anim == .sleep {
            burst = CatBurst(image: "cat_z", count: 1, at: now)
            Haptics.tick()
            rest(.sit, for: Double.random(in: 2...3))
            return
        }
        switch Int.random(in: 0..<3) {
        case 0:
            burst = CatBurst(image: "cat_heart", count: 1, at: now)
            play(.jump)
            Haptics.land()
        case 1:
            play(.pounce)
            Haptics.impact()
        default:
            burst = CatBurst(image: "cat_heart", count: 3, at: now)
            rest(.sit, for: Double.random(in: 2...3))
            Haptics.purr()
        }
    }

    private func think() {
        guard Date.now >= busyUntil else { return }
        switch anim {
        case .sleep, .jump, .pounce:
            rest(.sit, for: Double.random(in: 2...4))
        case .walk:
            rest([.sit, .sit, .idle, .sleep].randomElement()!)
        default:
            if Double.random(in: 0..<1) < 0.6 { walk() } else { rest([.sit, .idle, .sleep].randomElement()!) }
        }
    }

    private func rest(_ next: CatAnim, for duration: Double? = nil) {
        let range: ClosedRange<Double> = switch next {
        case .sleep: 8...16
        case .sit: 3...6
        default: 2...4
        }
        set(next, for: duration ?? .random(in: range))
    }

    private func play(_ next: CatAnim) {
        set(next, for: next.duration + 0.2)
    }

    private func walk() {
        let now = Date.now
        let x = glide.x(at: now)
        let target = x < 0.5 ? CGFloat.random(in: (x + 0.25)...1) : CGFloat.random(in: 0...(x - 0.25))
        let duration = Double(abs(target - x) * max(width - Self.margin * 2, 1) / Self.speed)
        facesLeft = target < x
        glide = Glide(from: x, to: target, start: now, duration: duration)
        set(.walk, for: duration)
    }

    private func set(_ next: CatAnim, for duration: Double) {
        anim = next
        animStart = .now
        busyUntil = .now.addingTimeInterval(duration)
    }
}

private struct ButtonCatSprite: View {
    let width: CGFloat

    private var cat: ButtonCat { .shared }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let date = context.date
            let x = cat.x(at: date)
            ZStack {
                PixelSprite(
                    sheet: cat.anim.sheet,
                    frames: cat.anim.frames,
                    frame: cat.anim.frame(after: date.timeIntervalSince(cat.animStart)),
                    size: CGSize(width: ButtonCat.size, height: ButtonCat.size),
                    flipped: cat.facesLeft
                )
                .padding(6)
                .contentShape(Rectangle())
                .onTapGesture { cat.tap() }
                .position(x: x, y: ButtonCat.size / 2)

                if let shownAt = cat.nameShownAt, date.timeIntervalSince(shownAt) < ButtonCat.nameDuration {
                    let tailOnRight = x > width / 2
                    let head = x + (cat.facesLeft ? -7 : 7)
                    let center = tailOnRight ? head + 5 - ButtonCat.nameWidth / 2 : head - 5 + ButtonCat.nameWidth / 2
                    CatBubble(tailOnRight: tailOnRight) {
                        Image("cat_name")
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 62, height: 14)
                    }
                    .frame(width: ButtonCat.nameWidth)
                    .offset(y: Int(date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2) ? 0 : -1)
                    .allowsHitTesting(false)
                    .position(x: min(max(center, ButtonCat.nameWidth / 2), width - ButtonCat.nameWidth / 2), y: -4)
                }

                if let burst = cat.burst, date.timeIntervalSince(burst.at) < 1.6 {
                    ForEach(0..<burst.count, id: \.self) { index in
                        let age = CGFloat(date.timeIntervalSince(burst.at)) - CGFloat(index) * 0.2
                        let spread = CGFloat(index) - CGFloat(burst.count - 1) / 2
                        Image(burst.image)
                            .interpolation(.none)
                            .opacity(age > 0 ? max(1 - age / 1.2, 0) : 0)
                            .position(x: x + spread * 7, y: 4 - max(age, 0) * 20)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: ButtonCat.size)
        .offset(y: -ButtonCat.size - 2)
        .onChange(of: width, initial: true) { cat.width = width }
        .task { await cat.run() }
        .accessibilityHidden(true)
    }
}
