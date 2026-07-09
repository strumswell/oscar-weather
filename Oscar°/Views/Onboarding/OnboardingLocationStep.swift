//
//  OnboardingLocationStep.swift
//  Oscar°
//

import CoreLocation
import SwiftUI

/// Third screen: why Oscar° wants the location, with the actual system prompt
/// behind the primary button. Resolves with `true` once access is granted and
/// `false` when the user declines either the step or the system prompt.
struct OnboardingLocationStep: View {
    let onResolved: (_ granted: Bool) -> Void

    private let locationService = LocationService.shared
    @State private var requested = false
    @State private var appeared = false

    var body: some View {
        OnboardingStageLayout {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 12) {
                            OnboardingStepIcon(systemImage: "location.fill", tint: .blue)
                                .onboardingEntrance(appeared, delay: 0.05, scale: 0.6)
                            VStack(spacing: 8) {
                                Text("Dein Wetter. Genau hier.")
                                    .font(.system(.title, design: .rounded, weight: .bold))
                                    .multilineTextAlignment(.center)
                                Text("Mit deinem Standort zeigt Oscar° die Vorhersage für den Ort, an dem du gerade bist – zu Hause wie unterwegs.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .onboardingEntrance(appeared, delay: 0.12)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 18) {
                            OnboardingBenefitRow(
                                systemImage: "cloud.sun.fill",
                                iconTint: .orange,
                                title: "Minutengenau für deinen Ort",
                                detail: "Temperatur, Regen und Wind exakt für deine Koordinaten."
                            )
                            .onboardingEntrance(appeared, delay: 0.22)
                            OnboardingBenefitRow(
                                systemImage: "figure.walk",
                                iconTint: .green,
                                title: "Reist automatisch mit",
                                detail: "Neuer Ort, neue Vorhersage – ganz ohne Suchen."
                            )
                            .onboardingEntrance(appeared, delay: 0.3)
                            OnboardingBenefitRow(
                                systemImage: "lock.fill",
                                iconTint: .blue,
                                title: "Privat by Design",
                                detail: "Dein Standort verlässt dein Gerät nur auf ca. 100 m gerundet und wird nur für eine Sache verwendet: dein Wetter."
                            )
                            .onboardingEntrance(appeared, delay: 0.38)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)

                OnboardingButtonStack(
                    primaryTitle: "Mein Wetter anzeigen",
                    primaryAction: requestPermission,
                    secondaryTitle: "Jetzt nicht",
                    secondaryAction: { onResolved(false) }
                )
                .onboardingEntrance(appeared, delay: 0.46)
            }
        }
        .onAppear { appeared = true }
        .onChange(of: locationService.authStatus) { _, status in
            guard requested, let status else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                onResolved(true)
            case .denied, .restricted:
                onResolved(false)
            default:
                break
            }
        }
    }

    private func requestPermission() {
        requested = true
        locationService.requestAuthorization()
    }
}

#Preview {
    ZStack {
        OnboardingSceneView(scene: .night)
        OnboardingStage()
        OnboardingLocationStep { _ in }
    }
    .environment(Weather.mock)
}
