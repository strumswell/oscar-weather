//
//  ForecastModelSettingsView.swift
//  Oscar°
//

import SwiftUI

struct ForecastModelSettingsView: View {
  private let settingsService = SettingService.shared

  var body: some View {
    List {
      ForEach(ForecastModelPreference.Group.allCases) { group in
        Section {
          ForEach(group.models) { model in
            ForecastModelRow(
              model: model,
              isSelected: settingsService.forecastModelPreference == model
            ) {
              settingsService.forecastModelPreference = model
            }
          }
        } header: {
          if let header = group.header {
            Text(header)
          }
        } footer: {
          footer(for: group)
        }
      }
    }
    .navigationBarTitle("Wettermodell", displayMode: .inline)
  }

  @ViewBuilder
  private func footer(for group: ForecastModelPreference.Group) -> some View {
    switch group {
    case .automatic:
      Text(
        "Standardmäßig wählt Oscar für jeden Ort automatisch das beste Modell und kombiniert mehrere Wetterdienste. Empfohlen für die meisten Nutzer."
      )
    case .ecmwf:
      EmptyView()
    case .national:
      Text(
        "Überschreibe die automatische Auswahl nur, wenn du weißt, was du tust. Die meisten Modelle liefern weltweite Daten, sind aber auf ihre Heimatregion optimiert. Einige decken nur ihre Region ab und liefern teils weniger Daten als die automatische Auswahl."
      )
    }
  }
}

struct ForecastModelRow: View {
  let model: ForecastModelPreference
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(model.name)
            .fontWeight(.medium)
            .foregroundStyle(.primary)

          if let provider = model.provider {
            Text(provider)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if let combined = model.combinedModels {
            Text(combined)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if let summary = model.summary {
            Text(summary)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if let specs = specsLine {
            Text(specs)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }

          coverageText
        }

        Spacer(minLength: 0)

        if isSelected {
          Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var specsLine: String? {
    let parts = [model.resolutionText, model.forecastLengthText, model.updateFrequencyText]
      .compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  @ViewBuilder
  private var coverageText: some View {
    if let region = model.optimizedRegion {
      if model.regionalOnly {
        Text("Nur \(region) – andere Orte liefern keine Daten")
          .font(.caption2)
          .foregroundStyle(.orange)
      } else {
        Text("Optimiert für \(region) · weltweite Daten")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }
}

#Preview {
  NavigationStack {
    ForecastModelSettingsView()
  }
}
