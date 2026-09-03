import SwiftUI

enum ForecastDaytimeTemperatureRangeMode: String, CaseIterable, Identifiable {
  case sunriseSunset
  case customHours

  var id: String { rawValue }

  var label: LocalizedStringKey {
    switch self {
    case .sunriseSunset:
      return "Sonnenaufgang bis Sonnenuntergang"
    case .customHours:
      return "Benutzerdefiniert"
    }
  }
}
