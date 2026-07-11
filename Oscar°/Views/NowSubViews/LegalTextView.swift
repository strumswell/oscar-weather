//
//  LegalTextView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.01.24.
//

import SwiftUI

struct LegalTextView: View {
    @Environment(NowPresentationCoordinator.self) private var presentation

    var body: some View {
        HStack {
            Spacer()
            Image(systemName: "gearshape")
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundStyle(Color(UIColor.label))
            Text("Einstellungen")
                .foregroundStyle(Color(UIColor.label))
                .font(.system(size: 12))
                .bold()
            Spacer()
        }
        .padding(.top)
        .padding(.bottom, 50)
        .scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.8)
                .scaleEffect(phase.isIdentity ? 1 : 0.99)
                .blur(radius: phase.isIdentity ? 0 : 0.5)
        }
        .onTapGesture {
            UIApplication.shared.playHapticFeedback()
            presentation.present(.legal)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Öffnet die rechtlichen Hinweise"))
        .accessibilityIdentifier("now.legal")
        .accessibilityAction {
            UIApplication.shared.playHapticFeedback()
            presentation.present(.legal)
        }
    }
}

#Preview {
    LegalTextView()
        .environment(NowPresentationCoordinator())
}
