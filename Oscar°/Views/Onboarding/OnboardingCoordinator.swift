//
//  OnboardingCoordinator.swift
//  Oscar°
//

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingCoordinator {
    static let shared = OnboardingCoordinator()
    nonisolated static let hasCompletedDefaultsKey = "hasCompletedOnboarding"

    nonisolated static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: hasCompletedDefaultsKey)
    }

    var isPresented: Bool

    private init() {
        isPresented = !Self.hasCompleted || Self.completionIsStale
    }

    private static var completionIsStale: Bool {
        guard !ScreenshotMode.active else { return false }
        let status = LocationService.shared.authStatus
        let authorized = status == .authorizedWhenInUse || status == .authorizedAlways
        return !authorized && CityService.shared.cities.isEmpty
    }

    func complete() {
        UserDefaults.standard.set(true, forKey: Self.hasCompletedDefaultsKey)
        isPresented = false
    }

    func replay() {
        isPresented = true
    }
}
