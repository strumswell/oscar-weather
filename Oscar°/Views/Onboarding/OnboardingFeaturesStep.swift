//
//  OnboardingFeaturesStep.swift
//  Oscar°
//

import SwiftUI

/// Second screen: the drifting component collage fills the hero window
/// (mounted by OnboardingView beneath the stage canvas, so the feather fades
/// it out) while the pitch reads on solid ground below.
struct OnboardingFeaturesStep: View {
    let onContinue: () -> Void

    @State private var appeared = false

    var body: some View {
        OnboardingStageLayout {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 12) {
                            OnboardingStepIcon(systemImage: "cloud.sun.fill", tint: .orange)
                                .onboardingEntrance(appeared, delay: 0.05, scale: 0.6)
                            VStack(spacing: 8) {
                                Text("Mehr als eine Vorhersage")
                                    .font(.system(.title, design: .rounded, weight: .bold))
                                    .multilineTextAlignment(.center)
                                Text("Oscar° bündelt präzise Vorhersagen, Echtzeit-Radar und Klimadaten verschiedener Wetterdienste.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .onboardingEntrance(appeared, delay: 0.12)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 18) {
                            OnboardingBenefitRow(
                                systemImage: "sun.max.fill",
                                iconTint: .yellow,
                                title: "Alles auf einen Blick",
                                detail: "Ein Wetterbericht mit allem, was Du wissen musst."
                            )
                            .onboardingEntrance(appeared, delay: 0.2)
                            OnboardingBenefitRow(
                                systemImage: "chart.xyaxis.line",
                                iconTint: .purple,
                                title: "So tief du willst",
                                detail: "Ensembles, detaillierte Charts und auf Wunsch dein bevorzugtes Wettermodell."
                            )
                            .onboardingEntrance(appeared, delay: 0.27)
                            OnboardingBenefitRow(
                                systemImage: "dot.radiowaves.left.and.right",
                                iconTint: .green,
                                title: "Radar & Karten",
                                detail: "Regen, Temperatur, Wind und Luftdruck live auf der Karte, minutengenau für die nächsten Stunden."
                            )
                            .onboardingEntrance(appeared, delay: 0.34)
                            OnboardingBenefitRow(
                                systemImage: "globe.europe.africa.fill",
                                iconTint: .teal,
                                title: "Offene Daten. Für immer kostenlos.",
                                detail: "Ermöglicht durch DWD, NOAA, ECMWF, MeteoSwiss und viele mehr."
                            )
                            .onboardingEntrance(appeared, delay: 0.41)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)

                OnboardingButtonStack(primaryTitle: "Weiter", primaryAction: onContinue)
                    .onboardingEntrance(appeared, delay: 0.48)
            }
        }
        .onAppear { appeared = true }
    }
}

#Preview {
    ZStack {
        OnboardingSceneView(scene: .day)
        OnboardingCollage()
        OnboardingStage()
        OnboardingFeaturesStep {}
    }
    .environment(Weather.mock)
}
