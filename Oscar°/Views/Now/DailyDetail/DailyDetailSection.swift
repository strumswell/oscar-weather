import SwiftUI

enum DailyDetailSection: String, CaseIterable, Identifiable {
  case temperature = "Temperatur"
  case precipitation = "Niederschlag"
  case wind = "Wind"

  var id: String { rawValue }
  var title: LocalizedStringKey { LocalizedStringKey(rawValue) }
}
