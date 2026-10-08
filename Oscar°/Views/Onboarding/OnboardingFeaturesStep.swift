//
//  OnboardingFeaturesStep.swift
//  Oscar°
//

import SwiftUI

/// The feature pages, in order. Each one has a visual in the hero window
/// (OnboardingFeatureStages.swift) and two lines of text on the canvas.
enum OnboardingFeaturePage: CaseIterable {
    case forecast
    case radar
    case ensemble
    case extras
}

/// The app tour: one page at a time, picture first. There is no skip; the
/// button walks through every page and then continues the flow.
struct OnboardingFeaturesStep: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = OnboardingFeaturePage.forecast
    /// The radar page's frames, built while the first page is read.
    @State private var radarGrids: Task<[[UInt8]], Never>?

    var body: some View {
        OnboardingStageLayout(layout: .tour) {
            VStack(spacing: 0) {
                OnboardingHeadline(title: page.title, copy: page.line)
                    .id(page)
                    .transition(.onboardingSlide(reduceMotion: reduceMotion))
                    .padding(.horizontal, OnboardingStage.edgePadding)
                    .padding(.top, OnboardingStage.canvasInset)

                Spacer(minLength: 16)

                PageDots(current: page)
                OnboardingButtonStack(primaryTitle: "Weiter", primaryAction: next)
            }
        } hero: {
            OnboardingFeatureStage(page: page, radarGrids: radarGrids)
                .id(page)
                .transition(.onboardingSlide(reduceMotion: reduceMotion))
        }
        .onAppear {
            if radarGrids == nil {
                radarGrids = Task { await OnboardingMapStage.buildGrids() }
            }
        }
    }

    private func next() {
        let pages = OnboardingFeaturePage.allCases
        guard let index = pages.firstIndex(of: page), index + 1 < pages.count else {
            onContinue()
            return
        }
        withAnimation(.smooth(duration: 0.5)) {
            page = pages[index + 1]
        }
    }
}

private extension OnboardingFeaturePage {
    var title: LocalizedStringKey {
        switch self {
        case .forecast: "Direkt vom Wetterdienst"
        case .radar: "Wo regnet es gerade?"
        case .ensemble: "Wie sicher ist die Vorhersage?"
        case .extras: "Und noch mehr"
        }
    }

    var line: LocalizedStringKey {
        switch self {
        case .forecast: "Oscar holt die Vorhersage von nationalen Wetterdiensten wie dem DWD in Deutschland oder NOAA in den USA."
        case .radar: "Sieh, wo es gerade regnet und wohin der Regen zieht. Dazu Karten für Temperatur, Wind und Luftdruck."
        case .ensemble: "Profis rechnen das Wetter dutzende Male durch. Oscar zeigt dir alle Läufe: Liegen sie eng beieinander, kannst du dich auf die Vorhersage verlassen."
        case .extras: "Messstationen, Luftqualität, Pollen, Klimadaten, Widgets und die Apple Watch. Kostenlos und ohne Werbung, für immer."
        }
    }
}

/// Where the reader is in the tour, so pages without a skip don't feel endless.
private struct PageDots: View {
    let current: OnboardingFeaturePage

    private let pages = OnboardingFeaturePage.allCases

    var body: some View {
        HStack(spacing: 8) {
            ForEach(pages, id: \.self) { page in
                Capsule()
                    .fill(page == current ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(width: page == current ? 18 : 7, height: 7)
            }
        }
        .padding(.bottom, 8)
        .animation(.smooth, value: current)
        .accessibilityElement()
        .accessibilityLabel(Text("Seite \(position) von \(pages.count)"))
    }

    private var position: Int {
        (pages.firstIndex(of: current) ?? 0) + 1
    }
}

#Preview {
    ZStack {
        OnboardingSceneView(scene: .day)
        OnboardingStage(layout: .tour)
        OnboardingFeaturesStep {}
    }
    .environment(Weather.mock)
}
