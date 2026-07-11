//
//  NotificationSettingsView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 07.04.26.
//

import SwiftUI
import UIKit

@MainActor
struct NotificationSettingsView: View {
    private let notificationSettingsManager: NotificationSettingsManager
    @State private var isUpdating = false
    @State private var showPermissionAlert = false

    init(notificationSettingsManager: NotificationSettingsManager = .shared) {
        self.notificationSettingsManager = notificationSettingsManager
    }

    var body: some View {
        Form {
            Section {
                // Read in body so @Observable tracks these; the toggles then reflect external
                // and async changes instead of going stale until the view is recreated.
                let rainAlertsEnabled = notificationSettingsManager.rainAlertsEnabled
                let weatherAlertsEnabled = notificationSettingsManager.weatherAlertsEnabled
                let liveRainStatusEnabled = notificationSettingsManager.liveRainStatusEnabled

                Toggle(
                    String(localized: "Rain alerts (Beta)"),
                    isOn: rainAlertsBinding(currentValue: rainAlertsEnabled)
                )
                .accessibilityIdentifier("notifications.rainAlerts")

                Toggle(
                    String(localized: "Weather alerts (Beta)"),
                    isOn: weatherAlertsBinding(currentValue: weatherAlertsEnabled)
                )
                .accessibilityIdentifier("notifications.weatherAlerts")

                Toggle(
                    String(localized: "Live-Regenstatus (Beta)"),
                    isOn: liveRainStatusBinding(currentValue: liveRainStatusEnabled)
                )
                .disabled(!rainAlertsEnabled)
                .accessibilityIdentifier("notifications.liveRainStatus")
            } footer: {
                Text(String(localized: "Der Live-Regenstatus zeigt aufziehenden Regen als Live-Aktivität auf dem Sperrbildschirm und in der Dynamic Island. Er benötigt aktive Regen-Warnungen."))
            }
            .disabled(isUpdating)

            Section {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if notificationSettingsManager.authorizationStatus == .denied {
                    Button(String(localized: "Systemeinstellungen öffnen")) {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "Alerts"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "Benachrichtigungen deaktiviert"), isPresented: $showPermissionAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "Allow notifications in iOS Settings to receive rain alerts and weather alerts in Central Europe and the United States."))
        }
        .task {
            await notificationSettingsManager.reloadNotificationStatus()
        }
    }

    private var statusText: String {
        switch notificationSettingsManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            if !notificationSettingsManager.rainAlertsEnabled && !notificationSettingsManager.weatherAlertsEnabled {
                return String(localized: "Both beta alert types are currently turned off. They are available for Central Europe and the United States.")
            }
            return String(localized: "Oscar can send beta rain alerts and beta weather alerts for your current location in Central Europe and the United States. Turn each alert type on or off below.")
        case .denied:
            return String(localized: "Mitteilungen sind auf Systemebene deaktiviert.")
        case .notDetermined:
            return String(localized: "Turn on rain alerts or weather alerts to receive beta notifications in Central Europe and the United States. Your approximate location will be stored on an Oscar server for this.")
        @unknown default:
            return String(localized: "Benachrichtigungsstatus unbekannt.")
        }
    }

    private func rainAlertsBinding(currentValue: Bool) -> Binding<Bool> {
        Binding(
            get: { currentValue },
            set: { newValue in
                runUpdate {
                    let enabled = await notificationSettingsManager.setRainAlertsEnabled(newValue)
                    if newValue && !enabled {
                        showPermissionAlert = true
                    }
                }
            }
        )
    }

    private func weatherAlertsBinding(currentValue: Bool) -> Binding<Bool> {
        Binding(
            get: { currentValue },
            set: { newValue in
                runUpdate {
                    let enabled = await notificationSettingsManager.setWeatherAlertsEnabled(newValue)
                    if newValue && !enabled {
                        showPermissionAlert = true
                    }
                }
            }
        )
    }

    private func liveRainStatusBinding(currentValue: Bool) -> Binding<Bool> {
        Binding(
            get: { currentValue },
            set: { newValue in
                runUpdate {
                    _ = await notificationSettingsManager.setLiveRainStatusEnabled(newValue)
                }
            }
        )
    }

    private func runUpdate(_ action: @escaping @MainActor () async -> Void) {
        isUpdating = true
        Task { @MainActor in
            await action()
            isUpdating = false
        }
    }
}

struct NotificationSettingsLabel: View {
    var body: some View {
        HStack {
            Image(systemName: "bell.badge.fill")
                .frame(width: 30, height: 30)
                .foregroundStyle(.white)
                .background(Color.blue)
                .clipShape(.rect(cornerRadius: 5))
            Text(String(localized: "Alerts"))
        }
    }
}

#Preview {
    NotificationSettingsView()
}
