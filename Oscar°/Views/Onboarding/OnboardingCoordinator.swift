//
//  OnboardingCoordinator.swift
//  Oscar°
//

import Foundation
import Observation

/// Presents the onboarding flow on first launch and on replay from settings.
/// Completion is stored in UserDefaults; LocationService reads the same key
/// (as a raw string, since it also compiles into targets without this type)
/// to leave the very first location prompt to the flow's location step.
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
        isPresented = !Self.hasCompleted
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
