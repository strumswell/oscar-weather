//
//  OnboardingStep.swift
//  Oscar°
//

import Foundation

enum OnboardingStep: String, Equatable {
    case welcome
    case features
    case location
    case manualLocation
    case notifications
    case crashReports
    case finale
}

extension OnboardingStep {
    @MainActor
    static func afterFeatures(locationService: LocationService) -> OnboardingStep {
        switch locationService.authStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return afterLocationResolved(locationService: locationService)
        case .denied, .restricted:
            if locationService.city.getSelectedCity() == nil {
                return .manualLocation
            }
            return afterLocationResolved(locationService: locationService)
        default:
            return .location
        }
    }

    @MainActor
    static func afterLocationResolved(locationService: LocationService) -> OnboardingStep {
        let notifications = NotificationSettingsManager.shared
        if notifications.authorizationStatus == .notDetermined,
           !notifications.enabled,
           OnboardingRegion.hasAlertCoverage(locationService.knownCoordinates() ?? locationService.getCoordinates()) {
            return .notifications
        }
        return afterNotifications
    }

    static var afterNotifications: OnboardingStep {
        CrashReporting.hasAnswered ? .finale : .crashReports
    }
}
