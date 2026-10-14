//
//  OnboardingBackgroundView.swift
//  Oscar°
//

import SwiftUI

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
            content
                .opacity(isFinale ? 0 : 1)
                .animation(.easeInOut(duration: 0.9), value: isFinale)

            if isFinale {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .transition(.identity)
            }
        }
        .onAppear {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                if let first = backdrop(for: step) { backdrop = first }
            }
        }
        .onChange(of: step) { _, next in
            if let next = backdrop(for: next) {
                backdrop = next
            }
        }
        .onChange(of: hasChosenCity) {
            if let next = backdrop(for: step) {
                backdrop = next
            }
        }
    }

    @ViewBuilder private var content: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            switch backdrop {
            case .scene(let scene):
                OnboardingSceneView(scene: scene)
                    .id(scene)
                    .transition(.opacity)
            case .live:
                WeatherSimulationView()
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
