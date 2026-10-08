//
//  OnboardingStage.swift
//  Oscar°
//

import SwiftUI

/// The solid canvas behind the middle onboarding steps. Animated scenes
/// (sky, simulation, feature visuals) stay inside a window at the top of the
/// screen and feather into this surface, so titles, copy, and controls always
/// sit on solid ground instead of the busy backdrop.
struct OnboardingStage: View {
    /// How the screen splits between the scene and the canvas. The canvas
    /// takes a share of the screen, clamped so iPad keeps a phone-sized
    /// canvas and gives the rest to the scene.
    enum Layout {
        /// One question, a short explanation and the buttons.
        case question
        /// Toggles with previews: almost all canvas, a strip of scene.
        case list
        /// The feature tour: mostly picture, a headline, two lines, a button.
        case tour

        func canvasTop(screenHeight h: CGFloat) -> CGFloat {
            let (share, lowest, highest): (CGFloat, CGFloat, CGFloat) = switch self {
            case .question: (0.52, 400, 560)
            case .list: (0.84, 0, 780)
            case .tour: (0.36, 300, 420)
            }
            return h - min(max(h * share, lowest), highest)
        }
    }

    var layout = Layout.question

    /// Phone width on iPad and Mac, centered. Text and buttons share it.
    static let contentMaxWidth: CGFloat = 480
    /// Distance from the screen edge to text and buttons.
    static let edgePadding: CGFloat = 24
    /// Distance from the solid canvas edge down to the first line of a step.
    static let canvasInset: CGFloat = 28
    /// Height of the gradient that dissolves the hero window into the canvas.
    static let featherHeight: CGFloat = 120

    /// The night-blue page Oscar's cards are designed for, also the Lock
    /// Screen sky of the rain Live Activity.
    static let navy = LinearGradient(
        colors: [
            Color(hue: 0.60, saturation: 0.58, brightness: 0.36),
            Color(hue: 0.64, saturation: 0.78, brightness: 0.14),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: max(layout.canvasTop(screenHeight: proxy.size.height) - Self.featherHeight, 0))

                LinearGradient(
                    colors: [Color(uiColor: .systemBackground).opacity(0), Color(uiColor: .systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Self.featherHeight)

                Color(uiColor: .systemBackground)
                    // Paints under the translucent keyboard and the home
                    // indicator, which would otherwise sample the sky.
                    .ignoresSafeArea(.all, edges: .bottom)
            }
        }
        // The keyboard is not ignored: the stage measures above it, so the
        // hero window shrinks and the content keeps its room.
        .ignoresSafeArea(.container)
        .allowsHitTesting(false)
    }
}

/// Lays a step out against the stage: `hero` sits centered in the window
/// above the canvas (empty for most steps, so the scene behind shows),
/// `content` starts where the canvas is fully solid.
struct OnboardingStageLayout<Hero: View, Content: View>: View {
    var layout = OnboardingStage.Layout.question
    @ViewBuilder var content: Content
    @ViewBuilder var hero: Hero

    var body: some View {
        GeometryReader { proxy in
            // The stage paints edge to edge, so the canvas position derives
            // from the full screen height. The keyboard reports as an
            // oversized bottom inset and must not count as screen.
            let bottomInset = proxy.safeAreaInsets.bottom
            let keyboardlessBottom = bottomInset > 100 ? 0 : bottomInset
            let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + keyboardlessBottom
            let canvasTop = layout.canvasTop(screenHeight: screenHeight) - proxy.safeAreaInsets.top

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: max(canvasTop, 0))
                    .overlay { hero }

                content
                    .frame(maxWidth: OnboardingStage.contentMaxWidth, maxHeight: .infinity, alignment: .top)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

extension OnboardingStageLayout where Hero == EmptyView {
    init(layout: OnboardingStage.Layout = .question, @ViewBuilder content: () -> Content) {
        self.init(layout: layout, content: content, hero: { EmptyView() })
    }
}

/// Title, copy and an optional third line, centered at the top of the canvas.
/// The head of every canvas step.
struct OnboardingHeadline<Footer: View>: View {
    var icon: OnboardingStepIcon?
    let title: LocalizedStringKey
    let copy: LocalizedStringKey
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 8) {
            if let icon {
                icon.padding(.bottom, 8)
            }
            Text(title)
                .font(.onboardingTitle)
                .fixedSize(horizontal: false, vertical: true)
            Text(copy)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            footer
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

extension OnboardingHeadline where Footer == EmptyView {
    init(icon: OnboardingStepIcon? = nil, title: LocalizedStringKey, copy: LocalizedStringKey) {
        self.init(icon: icon, title: title, copy: copy, footer: { EmptyView() })
    }
}

extension Font {
    static let onboardingTitle = Font.system(.title, design: .rounded, weight: .bold)
}

extension AnyTransition {
    /// The flow's push: in from the right, out to the left. A crossfade
    /// when motion is reduced.
    static func onboardingSlide(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: 80).combined(with: .opacity),
            removal: .offset(x: -80).combined(with: .opacity)
        )
    }
}

/// Standard entrance for canvas content: a fade with a small rise, staggered
/// per element by `delay`.
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
}

#Preview {
    ZStack {
        OnboardingSceneView(scene: .day)
            .environment(Weather.mock)
        OnboardingStage()
    }
}
