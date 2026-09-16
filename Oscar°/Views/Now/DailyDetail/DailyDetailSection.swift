import SwiftUI

enum DailyDetailSection: String, DetailSection {
  case temperature
  case precipitation
  case wind

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .temperature: "Temperatur"
    case .precipitation: "Niederschlag"
    case .wind: "Wind"
    }
  }
}
