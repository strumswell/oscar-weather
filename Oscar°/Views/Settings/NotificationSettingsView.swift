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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
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

                Toggle(isOn: rainAlertsBinding(currentValue: rainAlertsEnabled)) {
                    HStack(spacing: 8) {
                        Text("Rain alerts")
                        BetaBadge()
                    }
                }
                .accessibilityIdentifier("notifications.rainAlerts")

                Toggle(isOn: weatherAlertsBinding(currentValue: weatherAlertsEnabled)) {
                    HStack(spacing: 8) {
                        Text("Weather alerts")
                        BetaBadge()
                    }
                }
                .accessibilityIdentifier("notifications.weatherAlerts")

                Toggle(isOn: liveRainStatusBinding(currentValue: liveRainStatusEnabled)) {
                    HStack(spacing: 8) {
                        Text("Live-Regenstatus")
                        BetaBadge()
                    }
                }
                .disabled(!rainAlertsEnabled)
                .accessibilityIdentifier("notifications.liveRainStatus")
            } footer: {
                Text("Der Live-Regenstatus zeigt aufziehenden Regen als Live-Aktivität auf dem Sperrbildschirm und in der Dynamic Island. Er benötigt aktive Regen-Warnungen.")
            }
            .disabled(isUpdating)

            Section {
                if notificationSettingsManager.authorizationStatus == .denied {
                    Button("Systemeinstellungen öffnen") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                }
            } footer: {
                Text(statusText)
            }
        }
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "Benachrichtigungen deaktiviert"), isPresented: $showPermissionAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text("Allow notifications in iOS Settings to receive rain alerts and weather alerts.")
        }
        .task {
            await notificationSettingsManager.reloadNotificationStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await notificationSettingsManager.reloadNotificationStatus() }
        }
    }

    private var statusText: String {
        switch notificationSettingsManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            if !notificationSettingsManager.rainAlertsEnabled && !notificationSettingsManager.weatherAlertsEnabled {
                return String(localized: "Both beta alert types are currently turned off. They are available in Europe, the United States, Taiwan, and Brazil (rain alerts only).")
            }
            return String(localized: "Oscar can send beta rain alerts and beta weather alerts for your current location. Rain alerts cover the radar regions in Europe, the United States, Taiwan, and Brazil; weather alerts cover Europe, the United States, and Taiwan. Turn each alert type on or off below.")
        case .denied:
            return String(localized: "Mitteilungen sind auf Systemebene deaktiviert.")
        case .notDetermined:
            return String(localized: "Turn on rain alerts or weather alerts to receive beta notifications in Europe, the United States, Taiwan, and Brazil. Your approximate location will be stored on an Oscar server for this.")
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
                    let enabled = await notificationSettingsManager.setLiveRainStatusEnabled(newValue)
                    if newValue && !enabled {
                        showPermissionAlert = true
                    }
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

private struct BetaBadge: View {
    var body: some View {
        Text("Beta")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: .capsule)
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
