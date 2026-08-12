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
