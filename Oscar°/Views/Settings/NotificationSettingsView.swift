//
//  NotificationSettingsView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 07.04.26.
//

import CoreData
import SwiftUI
import UIKit

@MainActor
struct NotificationSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    private let manager = NotificationSettingsManager.shared
    @State private var isUpdating = false
    @State private var refusal: Refusal?

    var body: some View {
        let rainAlertsEnabled = manager.rainAlertsEnabled
        let weatherAlertsEnabled = manager.weatherAlertsEnabled
        let liveRainStatusEnabled = manager.liveRainStatusEnabled
        let notificationCityID = manager.notificationCity?.objectID
        let gpsAuthorized = LocationService.shared.gpsAuthorized
        let cities = CityService.shared.cities

        Form {
            if manager.authorizationStatus == .denied {
                Section {
                    Button("Systemeinstellungen öffnen") { openSettings(for: .notifications) }
                } footer: {
                    Text("Mitteilungen sind in den iOS-Einstellungen ausgeschaltet.")
                }
            }

            if gpsAuthorized || !cities.isEmpty {
                Section {
                    Picker(selection: Binding(get: { notificationCityID }, set: { id in
                        manager.setNotificationPlace(cities.first { $0.objectID == id })
                    })) {
                        if gpsAuthorized {
                            Text("Aktueller Standort").tag(NSManagedObjectID?.none)
                        }
                        ForEach(cities, id: \.objectID) { city in
                            Text(city.displayName).tag(Optional(city.objectID))
                        }
                    } label: {
                        Label("Ort", systemImage: "bell.fill")
                            .labelStyle(.settingsIcon(.red))
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Warnungen und die Regen-Live-Aktivität gelten für diesen Ort, auf etwa 100 m gerundet.")
                        if gpsAuthorized && notificationCityID == nil {
                            Text("Der aktuelle Standort wird aktualisiert, wenn du Oscar° öffnest.")
                        }
                    }
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
                    Text("Warnungen werden automatisch übernommen und können verzögert oder unvollständig sein. Maßgeblich ist der jeweilige Wetterdienst.")
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
}
