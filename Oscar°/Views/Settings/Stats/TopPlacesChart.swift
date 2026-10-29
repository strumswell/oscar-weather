import SwiftUI

struct TopPlacesChart: View {
    let places: [String: Int]

    var body: some View {
        let top = places.sorted { $0.value > $1.value }.prefix(5)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(top, id: \.key) { place, count in
                StatsBarRow(title: place, count: count, most: top.first?.value ?? 1, tint: .teal)
            }
            Text("So oft hat Oscar das Wetter für den Ort geladen, beim Öffnen und bei jeder Aktualisierung.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
