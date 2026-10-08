//
//  OnboardingCrashReportsStep.swift
//  Oscar°
//

import SwiftUI

/// Asks once whether crash and performance reports may go to Sentry. Nothing
/// is sent before the answer (see CrashReporting.isEnabled).
struct OnboardingCrashReportsStep: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingQuestionStep(
            icon: OnboardingStepIcon(systemImage: "wrench.and.screwdriver.fill", tint: .mint),
            title: "Darf ich Fehlerberichte bekommen?",
            copy: "Stürzt Oscar ab oder hakt, bekomme ich einen Bericht und kann den Fehler beheben. Gespeichert bei Sentry in der EU.",
            primaryTitle: "Ja, gerne",
            primaryAction: { answer(true) },
            secondaryTitle: "Lieber nicht",
            secondaryAction: { answer(false) }
        ) {
            Link("Was genau gesendet wird", destination: URL(string: "https://oscars.love/privacy")!)
                .font(.footnote.weight(.medium))
        }
    }

    private func answer(_ enabled: Bool) {
        CrashReporting.answer(enabled)
        onContinue()
    }
}

#Preview {
    ZStack {
        OnboardingSceneView(scene: .storm)
        OnboardingStage()
        OnboardingCrashReportsStep {}
    }
    .environment(Weather.mock)
}
