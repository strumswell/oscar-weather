//
//  SettingsIconLabelStyle.swift
//  Oscar°
//

import SwiftUI

struct SettingsIconLabelStyle: LabelStyle {
  let color: Color

  func makeBody(configuration: Configuration) -> some View {
    SettingsIconLabel(configuration: configuration, color: color)
  }
}

extension LabelStyle where Self == SettingsIconLabelStyle {
  static func settingsIcon(_ color: Color) -> SettingsIconLabelStyle {
    SettingsIconLabelStyle(color: color)
  }
}

private struct SettingsIconLabel: View {
  let configuration: LabelStyleConfiguration
  let color: Color

  @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 29

  var body: some View {
    HStack(spacing: 12) {
      configuration.icon
        .font(.callout.weight(.semibold))
        .foregroundStyle(.white)
        .frame(width: tileSize, height: tileSize)
        .background(color.gradient, in: .rect(cornerRadius: tileSize * 0.24))
      configuration.title
        .foregroundStyle(.primary)
    }
  }
}
