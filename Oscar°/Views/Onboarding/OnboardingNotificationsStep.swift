//
//  OnboardingNotificationsStep.swift
//  Oscar°
//

import SwiftUI

struct OnboardingNotificationsStep: View {
    let onContinue: () -> Void

    @State private var rainAlerts = true
    @State private var liveRain = true
    @State private var weatherAlerts = true
    @State private var enabling = false
    @State private var appeared = false

    private var anySelected: Bool { rainAlerts || weatherAlerts }

    var body: some View {
        OnboardingPage(heroShare: 0.22) {
            OnboardingSymbol(name: "bell.fill", tint: .red, appeared: appeared)
        } content: {
            VStack(spacing: 24) {
                Text("Wann soll sich Oscar melden?")
                    .font(.onboardingTitle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .onboardingEntrance(appeared, delay: 0.15)

                VStack(spacing: 0) {
                    NotificationChoice(title: "Bevor es regnet", detail: "Etwa eine Viertelstunde vorher.", isOn: $rainAlerts)
                    Divider().padding(.leading, 16)
                    NotificationChoice(title: "Unwetterwarnungen", detail: "Amtliche Warnungen für deinen Ort.", isOn: $weatherAlerts)
                    if RainRadarLiveActivityManager.isSupported {
                        Divider().padding(.leading, 16)
                        NotificationChoice(title: "Regen auf dem Sperrbildschirm", detail: "Live-Radar, solange es regnet.", isOn: $liveRain)
                            .disabled(!rainAlerts)
                    }
                }
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
                .catDash()
                .onboardingEntrance(appeared, delay: 0.25)
            }
        } buttons: {
            OnboardingButtonStack(
                primaryTitle: anySelected ? "Mitteilungen erlauben" : "Weiter",
                primaryDisabled: enabling,
                primaryAction: confirm,
                secondaryTitle: anySelected ? "Jetzt nicht" : nil,
                secondaryAction: onContinue
            )
            .onboardingEntrance(appeared, delay: 0.35)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: [rainAlerts, weatherAlerts, liveRain])
        .onAppear {
            appeared = true
            if OnboardingCoordinator.shared.replaying {
                let manager = NotificationSettingsManager.shared
                rainAlerts = manager.rainAlertsEnabled
                weatherAlerts = manager.weatherAlertsEnabled
                liveRain = manager.liveRainStatusEnabled
            }
        }
    }

    private func confirm() {
        guard !enabling else { return }
        enabling = true

        Task {
            let manager = NotificationSettingsManager.shared
            var granted = true
            if rainAlerts {
                granted = await manager.setRainAlertsEnabled(true)
            }
            if granted, weatherAlerts {
                granted = await manager.setWeatherAlertsEnabled(true)
            }
            if granted, rainAlerts, liveRain {
                _ = await manager.setLiveRainStatusEnabled(true)
            }
            enabling = false
            onContinue()
        }
    }
}

private struct NotificationChoice: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    OnboardingNotificationsStep {}
        .environment(Weather.mock)
        .preferredColorScheme(.dark)
}
