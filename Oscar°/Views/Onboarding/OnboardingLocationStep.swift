//
//  OnboardingLocationStep.swift
//  Oscar°
//

import CoreLocation
import SwiftUI

/// Why Oscar wants the location, with the actual system prompt behind the
/// primary button. Resolves with `true` once access is granted and `false`
/// when the user declines either the step or the system prompt.
struct OnboardingLocationStep: View {
    let onResolved: (_ granted: Bool) -> Void

    private let locationService = LocationService.shared
    @State private var requested = false

    var body: some View {
        OnboardingQuestionStep(
            icon: OnboardingStepIcon(systemImage: "location.fill", tint: .blue),
            title: "Darf Oscar deinen Standort nutzen?",
            copy: "Dann siehst du immer das Wetter da, wo du gerade bist, und Oscar kann dich warnen, bevor es bei dir regnet.",
            primaryTitle: "Standort freigeben",
            primaryAction: requestPermission,
            secondaryTitle: "Ort selbst suchen",
            secondaryAction: { onResolved(false) }
        ) {
            Text("Dein Standort wird auf etwa 100 Meter gerundet und nur fürs Wetter genutzt.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .onChange(of: locationService.authStatus) { _, status in
            guard requested, let status else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                onResolved(true)
            case .denied, .restricted:
                onResolved(false)
            default:
                break
            }
        }
    }

    private func requestPermission() {
        requested = true
        locationService.requestAuthorization()
    }
}

#Preview {
    ZStack {
        OnboardingSceneView(scene: .night)
        OnboardingStage()
        OnboardingLocationStep { _ in }
    }
    .environment(Weather.mock)
}
