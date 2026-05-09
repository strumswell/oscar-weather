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
    @ObservedObject private var notificationSettingsManager: NotificationSettingsManager
    @State private var isUpdating = false
    @State private var showPermissionAlert = false

    init() {
        _notificationSettingsManager = ObservedObject(wrappedValue: NotificationSettingsManager.shared)
    }

    init(notificationSettingsManager: NotificationSettingsManager) {
        _notificationSettingsManager = ObservedObject(wrappedValue: notificationSettingsManager)
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    String(localized: "Rain alerts (Beta)"),
                    isOn: rainAlertsEnabledBinding
                )

                Toggle(
                    String(localized: "Weather alerts (Beta)"),
                    isOn: weatherAlertsEnabledBinding
                )
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
            Text(String(localized: "Allow notifications in iOS Settings to receive rain alerts and weather alerts in Central Europe."))
        }
        .task {
            await notificationSettingsManager.reloadNotificationStatus()
        }
    }

    private var statusText: String {
        switch notificationSettingsManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            if !notificationSettingsManager.rainAlertsEnabled && !notificationSettingsManager.weatherAlertsEnabled {
                return String(localized: "Both beta alert types are currently turned off. They are only available for Central Europe.")
            }
            return String(localized: "Oscar can send beta rain alerts and beta weather alerts for your current location in Central Europe. Turn each alert type on or off below.")
        case .denied:
            return String(localized: "Mitteilungen sind auf Systemebene deaktiviert.")
        case .notDetermined:
            return String(localized: "Turn on rain alerts or weather alerts to receive beta notifications in Central Europe. Your approximate location will be stored on an Oscar server for this.")
        @unknown default:
            return String(localized: "Benachrichtigungsstatus unbekannt.")
        }
    }

    private var rainAlertsEnabledBinding: Binding<Bool> {
        Binding(
            get: { notificationSettingsManager.rainAlertsEnabled },
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

    private var weatherAlertsEnabledBinding: Binding<Bool> {
        Binding(
            get: { notificationSettingsManager.weatherAlertsEnabled },
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
                .foregroundColor(.white)
                .background(Color.blue)
                .cornerRadius(5)
            Text(String(localized: "Alerts"))
        }
    }
}

struct NotificationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationSettingsView()
    }
}
