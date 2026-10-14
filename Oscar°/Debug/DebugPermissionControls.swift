//
//  DebugPermissionControls.swift
//  Oscar°
//

import CoreLocation
import SwiftUI
import UIKit
import UserNotifications

struct DebugPermissionControls: View {
    private let locationService = LocationService.shared
    private let notificationManager = NotificationSettingsManager.shared
    #if DEBUG
    @AppStorage(SupportNudge.forcedKey) private var forcesSupportNudge = false
    #endif

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
            #if DEBUG
            liveActivityRow
            Toggle(isOn: $forcesSupportNudge) {
                Text(verbatim: "Support cats")
            }
            .font(.caption)
            .fixedSize()
            #endif
        }
        .padding(.bottom, 12)
        .task {
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

    #if DEBUG
    private var liveActivityRow: some View {
        let phases: [RainRadarActivityAttributes.ContentState.Phase] = [.upcoming, .raining, .ending, .ended]
        return HStack(spacing: 6) {
            Text(verbatim: "Live Activity")
            ForEach(phases, id: \.self) { phase in
                Button {
                    try? RainRadarLiveActivityManager.shared.startPreview(phase: phase)
                } label: {
                    Text(verbatim: phase.rawValue)
                }
            }
            Button {
                Task { await RainRadarLiveActivityManager.shared.endAll() }
            } label: {
                Text(verbatim: "End")
            }
        }
        .font(.caption)
        .buttonStyle(.bordered)
    }
    #endif

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
