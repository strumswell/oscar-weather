//
//  OnboardingCoordinator.swift
//  Oscar°
//

import Foundation
import Observation

/// Presents the onboarding flow on first launch and on replay from settings.
/// Completion is stored in UserDefaults, but the flag alone is not trusted:
/// it is reconciled against the state a completed flow guarantees.
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

    /// A completed flow always leaves a location source behind: either GPS
    /// access or the manual step's city (its continue button requires one).
    /// The flag WITHOUT any source means it outlived the app's data — after a
    /// delete + reinstall, cfprefsd can resurrect UserDefaults from its cache
    /// while the Core Data store, a real file, stays deleted. Rerunning the
    /// flow is the only in-app path back to the location permission prompt,
    /// so a stale completion must not suppress it. Screenshot runs are exempt:
    /// they suppress onboarding by launch argument on a deliberately empty
    /// sandbox.
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

    /// Re-runs the flow from settings; the completed flag stays set so an
    /// interrupted replay never turns into a forced onboarding at next launch.
    func replay() {
        isPresented = true
    }
}
