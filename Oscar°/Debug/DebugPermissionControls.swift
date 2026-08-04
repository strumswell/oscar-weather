//
//  DebugPermissionControls.swift
//  Oscar°
//

import CoreLocation
import SwiftUI
import UIKit
import UserNotifications

/// Debug-menu recovery for the two system permissions. Each row shows the live
/// status and re-requests while the prompt can still appear (notDetermined);
/// after a decision iOS never shows the prompt again, so the button deep-links
/// to the app's Settings page instead. Exists to exercise the states a
/// delete + reinstall can leave behind: iOS may retain the old install's
/// denial, stranding the app without any in-app path to the prompt.
struct DebugPermissionControls: View {
    private let locationService = LocationService.shared
    private let notificationManager = NotificationSettingsManager.shared

    var body: some View {
        VStack(spacing: 8) {
            Text(verbatim: "Permissions")
            row(
                name: "Location",
                status: locationStatusName,
                canPrompt: locationService.authStatus == .notDetermined || locationService.authStatus == nil
            ) {
                locationService.requestAuthorization()
            }
            row(
                name: "Notifications",
                status: notificationStatusName,
                canPrompt: notificationManager.authorizationStatus == .notDetermined
            ) {
                Task { await notificationManager.requestPermissionOnly() }
            }
        }
        .padding(.bottom, 12)
        .task {
            // A Settings round-trip changes the notification status without
            // any delegate callback; re-read whenever the panel comes up.
            await notificationManager.reloadNotificationStatus()
        }
    }

    private func row(
        name: String,
        status: String,
        canPrompt: Bool,
        request: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(name): \(status)")
            Button {
                if canPrompt {
                    request()
                } else if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(verbatim: canPrompt ? "Request" : "Settings")
            }
            .buttonStyle(.bordered)
        }
    }

    private var locationStatusName: String {
        switch locationService.authStatus {
        case .authorizedAlways: "always"
        case .authorizedWhenInUse: "whenInUse"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "notDetermined"
        case nil: "unknown"
        @unknown default: "unknown"
        }
    }

    private var notificationStatusName: String {
        switch notificationManager.authorizationStatus {
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown"
        }
    }
}
