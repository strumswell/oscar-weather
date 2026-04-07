//
//  RainAlertSettingsView.swift
//  RainAlertSettingsView
//
//  Created by Philipp Bolte on 07.04.26.
//

import SwiftUI
import UIKit

struct RainAlertSettingsView: View {
  @StateObject private var rainAlertManager = RainAlertManager.shared
  @State private var isUpdating = false
  @State private var showPermissionAlert = false

  var body: some View {
    Form {
      Section {
        Toggle(
          String(localized: "Regenwarnungen (Beta)"),
          isOn: Binding(
            get: { rainAlertManager.isEnabled },
            set: { newValue in
              isUpdating = true
              Task {
                if newValue {
                  let enabled = await rainAlertManager.enableAlerts()
                  if !enabled {
                    showPermissionAlert = true
                  }
                } else {
                  await rainAlertManager.disableAlerts()
                }
                isUpdating = false
              }
            }
          )
        )
        .disabled(isUpdating)
      }

      Section {
        Text(statusText)
          .font(.footnote)
          .foregroundColor(.secondary)

        if rainAlertManager.authorizationStatus == .denied {
          Button(String(localized: "Systemeinstellungen öffnen")) {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
          }
        }
      }
    }
    .navigationTitle(String(localized: "Regenwarnungen (Beta)"))
    .navigationBarTitleDisplayMode(.inline)
    .alert(String(localized: "Benachrichtigungen deaktiviert"), isPresented: $showPermissionAlert) {
      Button(String(localized: "OK"), role: .cancel) {}
    } message: {
      Text(String(localized: "Erlaube Mitteilungen in den iOS Einstellungen, um Regenwarnungen zu erhalten."))
    }
    .task {
      await rainAlertManager.reloadNotificationStatus()
    }
  }

  private var statusText: String {
    switch rainAlertManager.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return String(localized: "Regenwarnungen werden für deinen aktuellen Ort innerhalb von Mitteleuropa gesendet.")
    case .denied:
      return String(localized: "Mitteilungen sind auf Systemebene deaktiviert.")
    case .notDetermined:
      return String(localized: "Aktiviere Regenwarnungen (Beta) für Mitteleuropa, um Mitteilungen bei bevorstehendem Regen zu erhalten. Dein ungefährer Standort wird dazu auf einem Oscar-Server gespeichert.")
    @unknown default:
      return String(localized: "Benachrichtigungsstatus unbekannt.")
    }
  }
}

struct RainAlertSettingsLabel: View {
  var body: some View {
    HStack {
      Image(systemName: "bell.badge.fill")
        .frame(width: 30, height: 30)
        .foregroundColor(.white)
        .background(Color.blue)
        .cornerRadius(5)
      Text(String(localized: "Regenwarnungen (Beta)"))
    }
  }
}

struct RainAlertSettingsView_Previews: PreviewProvider {
  static var previews: some View {
      RainAlertSettingsView()
  }
}

