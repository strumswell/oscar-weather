import SwiftUI

enum DailyDetailSection: String, CaseIterable, Identifiable {
  case temperature = "Temperatur"
  case precipitation = "Niederschlag"
  case wind = "Wind"

  var id: String { rawValue }
  var title: LocalizedStringKey { LocalizedStringKey(rawValue) }
}

struct DailyDetailSegmentedControl: View {
  @Binding var selectedSection: DailyDetailSection

  var body: some View {
    Picker("Ensemble-Details", selection: $selectedSection) {
      ForEach(DailyDetailSection.allCases) { section in
        Text(section.title).tag(section)
      }
    }
    .pickerStyle(.segmented)
    .padding(6)
    .background(.thinMaterial, in: .rect(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(.white.opacity(0.08), lineWidth: 1)
    }
    .padding(.horizontal)
    .padding(.top, 8)
    .padding(.bottom, 4)
  }
}
