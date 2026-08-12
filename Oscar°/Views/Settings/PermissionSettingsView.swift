//
//  PermissionSettingsView.swift
//  Oscar°
//

import CoreLocation
import SwiftUI
import UIKit
import UserNotifications

/// The two system permissions as switches: while undetermined the switch
/// triggers the real prompt, afterwards it deep-links into Settings.
struct PermissionSettingsView: View {
  @Environment(\.openURL) private var openURL
  private let locationService = LocationService.shared
  private let notificationManager = NotificationSettingsManager.shared

  var body: some View {
    Form {
      Section {
        // Read in body so @Observable tracks the statuses (see NotificationSettingsView).
        let locationAuthorized = locationService.authStatus == .authorizedAlways
          || locationService.authStatus == .authorizedWhenInUse
        let locationUndetermined = locationService.authStatus == .notDetermined
          || locationService.authStatus == nil
        let notificationsAuthorized = isNotificationsAuthorized
        let notificationsUndetermined = notificationManager.authorizationStatus == .notDetermined

        Toggle(isOn: permissionBinding(
          currentValue: locationAuthorized,
          canPrompt: locationUndetermined,
          request: { locationService.requestAuthorization() },
          settingsURL: URL(string: UIApplication.openSettingsURLString)
        )) {
          Label("Standort", systemImage: "location.fill")
            .labelStyle(.settingsIcon(.blue))
        }

        Toggle(isOn: permissionBinding(
          currentValue: notificationsAuthorized,
          canPrompt: notificationsUndetermined,
          request: { Task { await notificationManager.requestPermissionOnly() } },
          settingsURL: URL(string: UIApplication.openNotificationSettingsURLString)
        )) {
          Label("Mitteilungen", systemImage: "app.badge.fill")
            .labelStyle(.settingsIcon(.red))
        }
      } footer: {
        Text("Berechtigungen verwaltet iOS: Beim ersten Aktivieren fragt Oscar direkt an, danach öffnet der Schalter die passende Stelle in den iOS-Einstellungen.")
      }
    }
    .navigationTitle("Berechtigungen")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await notificationManager.reloadNotificationStatus()
    }
  }

  private var isNotificationsAuthorized: Bool {
    switch notificationManager.authorizationStatus {
    case .authorized, .provisional, .ephemeral: true
    default: false
    }
  }

  private func permissionBinding(
    currentValue: Bool,
    canPrompt: Bool,
    request: @escaping () -> Void,
    settingsURL: URL?
  ) -> Binding<Bool> {
    Binding(
      get: { currentValue },
      set: { _ in
        if canPrompt {
          request()
        } else if let settingsURL {
          openURL(settingsURL)
        }
      }
    )
  }
}

#Preview {
  NavigationStack {
    PermissionSettingsView()
  }
}
