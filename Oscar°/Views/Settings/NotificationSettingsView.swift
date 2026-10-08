//
//  NotificationSettingsView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 07.04.26.
//

import SwiftUI
import UIKit

/// Rain alerts, the rain Live Activity and official weather warnings.
@MainActor
struct NotificationSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(Location.self) private var location
    private let manager = NotificationSettingsManager.shared
    @State private var isUpdating = false
    @State private var refusal: Refusal?

    var body: some View {
        // Read in body so @Observable tracks these; the toggles then reflect external
        // and async changes instead of going stale until the view is recreated.
        let rainAlertsEnabled = manager.rainAlertsEnabled
        let weatherAlertsEnabled = manager.weatherAlertsEnabled
        let liveRainStatusEnabled = manager.liveRainStatusEnabled

        Form {
            if manager.authorizationStatus == .denied {
                Section {
                    Button("Systemeinstellungen öffnen") { openSettings(for: .notifications) }
                } footer: {
                    Text("Mitteilungen sind in den iOS-Einstellungen ausgeschaltet.")
                }
            }

            Section {
                Toggle(isOn: toggle(rainAlertsEnabled, refusal: .notifications, update: manager.setRainAlertsEnabled)) {
                    Label("Regenwarnungen", systemImage: "cloud.rain.fill")
                        .labelStyle(.settingsIcon(.blue))
                }
                .accessibilityIdentifier("notifications.rainAlerts")

                if RainRadarLiveActivityManager.isSupported {
                    Toggle(isOn: toggle(liveRainStatusEnabled, refusal: .liveActivities, update: manager.setLiveRainStatusEnabled)) {
                        Label("Regen-Live-Aktivität", systemImage: "lock.iphone")
                            .labelStyle(.settingsIcon(.indigo))
                    }
                    .disabled(!rainAlertsEnabled)
                    .accessibilityIdentifier("notifications.liveRainStatus")
                }
            } footer: {
                Text("Per Radar in Europa, den USA, Taiwan, Brasilien und auf den Kanaren.")
            }
            .disabled(isUpdating)

            Section {
                Toggle(isOn: toggle(weatherAlertsEnabled, refusal: .notifications, update: manager.setWeatherAlertsEnabled)) {
                    Label("Wetterwarnungen", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.settingsIcon(.orange))
                }
                .accessibilityIdentifier("notifications.weatherAlerts")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Amtliche Warnungen in Europa (DWD, MeteoAlarm), den USA (NWS) und Taiwan (CWA).")
                    if location.name.isEmpty {
                        Text("Gilt für den Ort, der gerade in Oscar° offen ist, auf etwa 100 m gerundet.")
                    } else {
                        Text("Gilt für \(location.name), den Ort, der gerade in Oscar° offen ist, auf etwa 100 m gerundet.")
                    }
                }
            }
            .disabled(isUpdating)
        }
        .navigationTitle("Benachrichtigungen")
        .navigationBarTitleDisplayMode(.inline)
        .alert(refusalTitle, isPresented: isRefusalPresented, presenting: refusal) { refusal in
            Button("Systemeinstellungen öffnen") { openSettings(for: refusal) }
            Button("Abbrechen", role: .cancel) {}
        } message: { refusal in
            switch refusal {
            case .notifications:
                Text("Erlaube Mitteilungen in den iOS-Einstellungen.")
            case .liveActivities:
                Text("Erlaube Live-Aktivitäten in den iOS-Einstellungen.")
            }
        }
        .task {
            await manager.reloadNotificationStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await manager.reloadNotificationStatus() }
        }
    }

    /// Why switching something on didn't stick.
    private enum Refusal {
        case notifications
        case liveActivities
    }

    private var refusalTitle: Text {
        switch refusal {
        case .liveActivities: Text("Live-Aktivitäten ausgeschaltet")
        default: Text("Benachrichtigungen deaktiviert")
        }
    }

    private var isRefusalPresented: Binding<Bool> {
        Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })
    }

    private func openSettings(for refusal: Refusal) {
        let target = refusal == .notifications
            ? UIApplication.openNotificationSettingsURLString
            : UIApplication.openSettingsURLString
        guard let url = URL(string: target) else { return }
        openURL(url)
    }

    private func toggle(
        _ currentValue: Bool,
        refusal: Refusal,
        update: @escaping @MainActor (Bool) async -> Bool
    ) -> Binding<Bool> {
        Binding(
            get: { currentValue },
            set: { newValue in
                isUpdating = true
                Task { @MainActor in
                    let enabled = await update(newValue)
                    if newValue && !enabled {
                        self.refusal = refusal
                    }
                    isUpdating = false
                }
            }
        )
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .environment(Location())
}
