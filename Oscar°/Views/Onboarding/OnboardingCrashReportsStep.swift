//
//  OnboardingCrashReportsStep.swift
//  Oscar°
//

import SwiftUI

struct OnboardingCrashReportsStep: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingQuestionStep(
            symbol: "checkmark",
            tint: .green,
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
