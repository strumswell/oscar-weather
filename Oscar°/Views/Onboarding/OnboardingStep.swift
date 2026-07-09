//
//  OnboardingStep.swift
//  Oscar°
//

import Foundation

/// The ordered screens of the onboarding flow. Permission steps are skipped
/// when their decision has already been made (replays, updating users).
enum OnboardingStep: Equatable {
    case welcome
    case features
    case location
    case manualLocation
    case notifications
    case finale
}

extension OnboardingStep {
    /// The step after the feature tour: ask for location only while the system
    /// prompt can still appear; a denied status routes to manual city selection
    /// unless a city is already picked.
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

    /// The step once a location source exists (or was explicitly skipped):
    /// notifications only where oscar-server's alert products have coverage
    /// and the permission hasn't been decided yet.
    @MainActor
    static func afterLocationResolved(locationService: LocationService) -> OnboardingStep {
        let notifications = NotificationSettingsManager.shared
        if notifications.authorizationStatus == .notDetermined,
           !notifications.enabled,
           OnboardingRegion.hasAlertCoverage(locationService.getCoordinates()) {
            return .notifications
        }
        return .finale
    }
}
