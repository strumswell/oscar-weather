//
//  SettingsExternalLink.swift
//  Oscar°
//

import SwiftUI

struct SettingsExternalLink<Label: View>: View {
  let destination: URL
  @ViewBuilder let label: () -> Label

  var body: some View {
    Link(destination: destination) {
      LabeledContent {
        Image(systemName: "arrow.up.right")
          .font(.footnote.bold())
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      } label: {
        label()
      }
    }
    .foregroundStyle(.primary)
  }
}

enum LegalPage {
  private static let german = Bundle.main.preferredLocalizations.first == "de"
  static let privacy = URL(string: german ? "https://oscars.love/de/datenschutz/" : "https://oscars.love/en/privacy/")!
  static let imprint = URL(string: german ? "https://oscars.love/de/impressum/" : "https://oscars.love/en/imprint/")!
}
