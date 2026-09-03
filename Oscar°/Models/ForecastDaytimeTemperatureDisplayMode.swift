import SwiftUI

enum ForecastDaytimeTemperatureDisplayMode: String, CaseIterable, Identifiable {
  case replaceValues
  case overlayOnDailyRange

  var id: String { rawValue }

  var label: LocalizedStringKey {
    switch self {
    case .replaceValues:
      return "Werte ersetzen"
    case .overlayOnDailyRange:
      return "Im Tagesverlauf markieren"
    }
  }
}
