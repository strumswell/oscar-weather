//
//  OnboardingTourStep.swift
//  Oscar°
//

import SwiftUI

enum OnboardingTourPage: String, CaseIterable {
    case forecast
    case map
    case ensemble
    case more

    static var staged: OnboardingTourPage? {
        guard ScreenshotMode.active else { return nil }
        return UserDefaults.standard.string(forKey: "onboardingTourPage").flatMap(OnboardingTourPage.init)
    }

    var title: LocalizedStringKey {
        switch self {
        case .forecast: "Dein Wetter"
        case .map: "Hauseigene Wetterkarten"
        case .ensemble: "Wie sicher ist das?"
        case .more: "Und noch viel mehr."
        }
    }

    var line: LocalizedStringKey {
        switch self {
        case .forecast: "Genaue Wetterberichte von lokalen und internationalen Wetterdiensten wie dem DWD, NOAA und vielen mehr. Ermöglicht durch Open-Meteo & Oscar Server."
        case .map: "Oscar Server visualisiert diverse Wettermodelle und Beobachtungen von Wetterdiensten. Von Radaren bis hin zu Windkarten."
        case .ensemble: "Werde zum Profi und schau dir Ensemble-Vorhersagen an. Diese visualisieren alle möglichen Wetterbedingungen und zeigen so wie sicher die Vorhersage ist."
        case .more: "Messstationen, Pollen, Luftqualität, Klima. Dazu Widgets und die Watch. Kostenlos, ohne Werbung."
        }
    }
}

struct OnboardingTourStep: View {
    @Binding var page: OnboardingTourPage
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        OnboardingPage(heroShare: OnboardingMetrics.tourHeroShare) {
            Color.clear
        } content: {
            VStack(spacing: 18) {
                PageDots(current: page)
                OnboardingHeadline(title: page.title, copy: page.line)
                    .id(page)
                    .transition(.onboardingSlide(reduceMotion: reduceMotion))
            }
            .onboardingEntrance(appeared, delay: 0.1)
        } buttons: {
            OnboardingButtonStack(primaryTitle: "Weiter", primaryAction: next)
                .onboardingEntrance(appeared, delay: 0.25)
        }
        .sensoryFeedback(.selection, trigger: page)
        .onAppear { appeared = true }
    }

    private func next() {
        let pages = OnboardingTourPage.allCases
        guard let index = pages.firstIndex(of: page), index + 1 < pages.count else {
            onContinue()
            return
        }
        withAnimation(.smooth(duration: 0.5)) {
            page = pages[index + 1]
        }
    }
}

private struct PageDots: View {
    let current: OnboardingTourPage

    private let pages = OnboardingTourPage.allCases

    var body: some View {
        HStack(spacing: 6) {
            ForEach(pages, id: \.self) { page in
                Capsule()
                    .fill(page == current ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(width: page == current ? 18 : 7, height: 7)
            }
        }
        .animation(.smooth, value: current)
        .accessibilityElement()
        .accessibilityLabel(Text("Seite \(position) von \(pages.count)"))
    }

    private var position: Int {
        (pages.firstIndex(of: current) ?? 0) + 1
    }
}
