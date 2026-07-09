//
//  OnboardingBackgroundView.swift
//  Oscar°
//

import SwiftUI

/// Shared backdrop behind the onboarding steps: dioramas that walk through a
/// day — noon behind welcome and features, a starry night behind the location
/// ask, a thunderstorm behind notifications — while the manual-city step shows
/// the real simulation crossfading to every place the search picks. The finale
/// keeps whatever is on screen and dissolves it over the frosted NowView.
struct OnboardingBackgroundView: View {
    let step: OnboardingStep
    @Environment(Location.self) private var location
    @State private var backdrop: Backdrop = .scene(.day)

    private enum Backdrop: Equatable {
        case scene(OnboardingSceneView.Scene)
        case live
    }

    var body: some View {
        ZStack {
            // The weather backdrop is opaque for every step; at the finale it
            // dissolves to reveal the NowView living beneath the whole flow.
            content
                .opacity(isFinale ? 0 : 1)
                .animation(.easeInOut(duration: 0.9), value: isFinale)

            if isFinale {
                // Full frost, present the very instant the finale begins (no
                // fade-in) so raw NowView is never exposed while the backdrop
                // above dissolves through it.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .transition(.identity)
            }
        }
        .onChange(of: step) { _, next in
            // The finale maps to nil: it keeps the previous backdrop while
            // the whole layer dissolves.
            if let next = backdrop(for: next) {
                backdrop = next
            }
        }
        .onChange(of: hasChosenCity) {
            // On the manual step the night sky holds until a city is picked,
            // then the live simulation takes over for that place.
            if let next = backdrop(for: step) {
                backdrop = next
            }
        }
    }

    @ViewBuilder private var content: some View {
        ZStack {
            // Opaque backing: scene crossfades dip below full opacity halfway
            // through, and without this NowView's big temperature grins
            // through the hero window for a beat.
            Color.black
                .ignoresSafeArea()

            switch backdrop {
            case .scene(let scene):
                OnboardingSceneView(scene: scene)
                    // Re-created per scene so a step change crossfades between
                    // two finished dioramas instead of hard-swapping snapshots.
                    .id(scene)
                    .transition(.opacity)
            case .live:
                WeatherSimulationView()
                    // Re-created per place so a city switch crossfades between
                    // two finished scenes instead of hard-swapping shader input.
                    .id(placeKey)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 1.1), value: backdrop)
        .animation(.easeInOut(duration: 1.1), value: placeKey)
    }

    private var isFinale: Bool { step == .finale }

    private var hasChosenCity: Bool {
        LocationService.shared.city.getSelectedCity() != nil
    }

    private func backdrop(for step: OnboardingStep) -> Backdrop? {
        switch step {
        case .welcome, .features: .scene(.day)
        case .location: .scene(.night)
        case .manualLocation: hasChosenCity ? .live : .scene(.night)
        case .notifications: .scene(.storm)
        case .finale: nil
        }
    }

    private var placeKey: String {
        String(format: "%.2f,%.2f", location.coordinates.latitude, location.coordinates.longitude)
    }
}
