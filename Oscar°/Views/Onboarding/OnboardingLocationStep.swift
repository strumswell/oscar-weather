//
//  OnboardingLocationStep.swift
//  Oscar°
//

import CoreLocation
import SwiftUI

struct OnboardingLocationStep: View {
    let onResolved: (_ granted: Bool) -> Void

    private let locationService = LocationService.shared
    @State private var requested = false

    var body: some View {
        OnboardingQuestionStep(
            symbol: "location.fill",
            tint: .blue,
            title: "Wo bist du gerade?",
            copy: "Dann zeigt Oscar das Wetter genau hier und sagt Bescheid, bevor es regnet.",
            primaryTitle: "Standort freigeben",
            primaryAction: requestPermission,
            secondaryTitle: "Ort selbst suchen",
            secondaryAction: { onResolved(false) }
        ) {
            Text("Auf etwa 100 Meter gerundet. Nur fürs Wetter.")
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
        switch locationService.authStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            onResolved(true)
        case .denied, .restricted:
            onResolved(false)
        default:
            requested = true
            locationService.requestAuthorization()
        }
    }
}
