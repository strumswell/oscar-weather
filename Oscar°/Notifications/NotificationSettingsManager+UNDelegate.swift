import UserNotifications

extension NotificationSettingsManager: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let request = notification.request
        notificationLogger.info("Lifecycle: willPresent notification; identifier=\(request.identifier, privacy: .public) trigger=\(String(describing: request.trigger), privacy: .public)")
        UsageStatsStore.shared.record { $0.notificationsShown += 1 }
        return UNNotificationPresentationOptions(arrayLiteral: .banner, .sound)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        notificationLogger.info("Lifecycle: didReceive notification response; identifier=\(request.identifier, privacy: .public) actionIdentifier=\(response.actionIdentifier, privacy: .public)")
        UsageStatsStore.shared.record { $0.notificationsOpened += 1 }
    }
}

extension UNAuthorizationStatus {
    var debugName: String {
        switch self {
        case .notDetermined:
            "notDetermined"
        case .denied:
            "denied"
        case .authorized:
            "authorized"
        case .provisional:
            "provisional"
        case .ephemeral:
            "ephemeral"
        @unknown default:
            "unknown"
        }
    }
}
