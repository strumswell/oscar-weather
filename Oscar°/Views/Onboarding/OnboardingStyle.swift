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
