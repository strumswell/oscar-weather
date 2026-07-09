//
//  OnboardingNotificationsStep.swift
//  Oscar°
//

import SwiftUI

/// Fifth screen (only where oscar-server has alert coverage): opt into rain
/// and weather alerts while a thunderstorm rages in the hero window. Enabling
/// requests the system permission and enrolls the device with oscar-server
/// through NotificationSettingsManager.
struct OnboardingNotificationsStep: View {
    let onContinue: () -> Void

    @State private var enabling = false
    @State private var appeared = false

    var body: some View {
        OnboardingStageLayout {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 12) {
                            OnboardingStepIcon(systemImage: "bell.badge.fill", tint: .red, wiggles: true)
                                .onboardingEntrance(appeared, delay: 0.05, scale: 0.6)
                            VStack(spacing: 8) {
                                Text("Wetter, das sich meldet.")
                                    .font(.system(.title, design: .rounded, weight: .bold))
                                    .multilineTextAlignment(.center)
                                Text("Oscar° sagt dir Bescheid, bevor dich das Wetter überrascht – nur dann, wenn es wirklich zählt.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .onboardingEntrance(appeared, delay: 0.12)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 18) {
                            OnboardingBenefitRow(
                                systemImage: "umbrella.fill",
                                iconTint: .blue,
                                title: "Regen im Anmarsch",
                                detail: "Eine kurze Warnung, bevor es an deinem Ort losregnet."
                            )
                            .onboardingEntrance(appeared, delay: 0.22)
                            OnboardingBenefitRow(
                                systemImage: "exclamationmark.triangle.fill",
                                iconTint: .orange,
                                title: "Amtliche Warnungen",
                                detail: "Unwetterwarnungen der offiziellen Wetterdienste für deinen Ort."
                            )
                            .onboardingEntrance(appeared, delay: 0.3)
                            OnboardingBenefitRow(
                                systemImage: "heart.fill",
                                iconTint: .pink,
                                title: "Kein Spam, versprochen",
                                detail: "Nur relevante Hinweise – jederzeit in den Einstellungen abschaltbar."
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
                    primaryTitle: "Benachrichtige mich",
                    primaryDisabled: enabling,
                    primaryAction: enableNotifications,
                    secondaryTitle: "Jetzt nicht",
                    secondaryAction: onContinue
                )
                .onboardingEntrance(appeared, delay: 0.46)
            }
        }
        .onAppear { appeared = true }
    }

    /// Turns on both alert types: the first call raises the system prompt and
    /// registers with APNs/oscar-server, the second just extends the
    /// subscription. A denied prompt simply moves on.
    private func enableNotifications() {
        guard !enabling else { return }
        enabling = true

        Task {
            let manager = NotificationSettingsManager.shared
            let granted = await manager.setRainAlertsEnabled(true)
            if granted {
                _ = await manager.setWeatherAlertsEnabled(true)
            }
            enabling = false
            onContinue()
        }
    }
}

#Preview {
    ZStack {
        OnboardingSceneView(scene: .storm)
        OnboardingStage()
        OnboardingNotificationsStep {}
    }
    .environment(Weather.mock)
}
