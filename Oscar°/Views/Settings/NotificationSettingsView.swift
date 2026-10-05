//
//  NotificationSettingsView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 07.04.26.
//

import SwiftUI
import UIKit

/// Rain alerts, the rain Live Activity and official weather warnings, each
/// with one short line. Copy mirrors oscar-server: rain up to 30 min ahead
/// from radar; warnings from DWD, MeteoAlarm, NWS and CWA; one rounded
/// location, deleted when everything is off.
@MainActor
struct NotificationSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
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
                AlertToggle(
                    title: "Regenwarnungen",
                    detail: "Bis zu 30 Minuten vorher.",
                    systemImage: "cloud.rain.fill",
                    tint: .blue,
                    isOn: toggle(rainAlertsEnabled, refusal: .notifications, update: manager.setRainAlertsEnabled)
                )
                .accessibilityIdentifier("notifications.rainAlerts")

                if RainRadarLiveActivityManager.isSupported {
                    AlertToggle(
                        title: "Live-Regenstatus",
                        detail: "Auf Sperrbildschirm und Dynamic Island.",
                        systemImage: "lock.iphone",
                        tint: .indigo,
                        isOn: toggle(liveRainStatusEnabled, refusal: .liveActivities, update: manager.setLiveRainStatusEnabled)
                    )
                    .disabled(!rainAlertsEnabled)
                    .accessibilityIdentifier("notifications.liveRainStatus")
                }
            } footer: {
                Text("Per Radar in Europa, den USA, Taiwan, Brasilien und auf den Kanaren.")
            }
            .disabled(isUpdating)

            Section {
                AlertToggle(
                    title: "Wetterwarnungen",
                    detail: "Von DWD, MeteoAlarm, NWS und CWA.",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange,
                    isOn: toggle(weatherAlertsEnabled, refusal: .notifications, update: manager.setWeatherAlertsEnabled)
                )
                .accessibilityIdentifier("notifications.weatherAlerts")
            }
            .disabled(isUpdating)

            Section {
                SettingsExternalLink(destination: URL(string: "https://oscars.love/privacy")!) {
                    Label("Datenschutz", systemImage: "hand.raised.fill")
                        .labelStyle(.settingsIcon(.blue))
                }
            } footer: {
                Text("Gilt für deinen aktuellen Standort, auf etwa 100 m gerundet. Schaltest du alles aus, wird er gelöscht.")
            }
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

/// A switch with its settings tile, a Beta tag and one line on what it does.
private struct AlertToggle: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let systemImage: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                        BetaBadge()
                    }
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage)
            }
            .labelStyle(.settingsIcon(tint))
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
