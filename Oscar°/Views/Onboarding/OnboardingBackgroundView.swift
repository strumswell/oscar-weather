//
//  OnboardingBackgroundView.swift
//  Oscar°
//

import SwiftUI

/// Shared backdrop behind the onboarding steps: dioramas that walk through a
/// day (noon, starry night, thunderstorm), while the manual-city step shows
/// the real simulation crossfading to every place the search picks. The
/// finale keeps whatever is on screen and dissolves it over the frosted NowView.
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
            // At the finale the backdrop dissolves to reveal NowView beneath.
            content
                .opacity(isFinale ? 0 : 1)
                .animation(.easeInOut(duration: 0.9), value: isFinale)

            if isFinale {
                // Instant frost, so raw NowView never shows through the dissolve.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .transition(.identity)
            }
        }
        .onAppear {
            // A flow that opens past welcome starts on its own scene, not a
            // crossfade from noon.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                if let first = backdrop(for: step) { backdrop = first }
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
            // Scene crossfades dip below full opacity halfway; this keeps
            // NowView from showing through for a beat.
            Color.black
                .ignoresSafeArea()

            switch backdrop {
            case .scene(let scene):
                OnboardingSceneView(scene: scene)
                    // One view per scene, so a step change crossfades.
                    .id(scene)
                    .transition(.opacity)
            case .live:
                WeatherSimulationView()
                    // One view per place, so a city switch crossfades.
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
        case .notifications, .crashReports: .scene(.storm)
        case .finale: nil
        }
    }

    private var placeKey: String {
        String(format: "%.2f,%.2f", location.coordinates.latitude, location.coordinates.longitude)
    }
}
