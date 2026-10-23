//
//  OnboardingStep.swift
//  Oscar°
//

import Foundation

enum OnboardingStep: String, Equatable {
    case welcome
    case tour
    case location
    case manualLocation
    case notifications
    case crashReports
    case finale
}

extension OnboardingStep {
    @MainActor
    static func afterTour(locationService: LocationService) -> OnboardingStep {
        guard !OnboardingCoordinator.shared.replaying else { return .location }
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
        guard !OnboardingCoordinator.shared.replaying else { return .notifications }
        let notifications = NotificationSettingsManager.shared
        if notifications.authorizationStatus == .notDetermined,
           !notifications.enabled,
           OnboardingRegion.hasAlertCoverage(locationService.knownCoordinates() ?? locationService.getCoordinates()) {
            return .notifications
        }
        return afterNotifications
    }

    @MainActor
    static var afterNotifications: OnboardingStep {
        guard !OnboardingCoordinator.shared.replaying else { return .crashReports }
        return CrashReporting.hasAnswered ? .finale : .crashReports
    }
}
