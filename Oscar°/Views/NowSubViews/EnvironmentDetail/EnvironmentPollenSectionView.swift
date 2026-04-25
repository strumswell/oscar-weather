import SwiftUI

struct EnvironmentPollenSectionView: View {
    let currentPollen: [PollenSnapshot]
    let dominantPollen: PollenSnapshot?
    let dominantPollenSeverityColor: Color
    let time: [Double]
    let alder: [Double?]
    let birch: [Double?]
    let grass: [Double?]
    let mugwort: [Double?]
    let ragweed: [Double?]
    let maxTimeRange: ClosedRange<Date>
    let referenceDate: Date
    @Binding var chartScrollPosition: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if currentPollen.isEmpty {
                EnvironmentDetailCard {
                    EnvironmentDetailEmptyStateView(
                        title: "Keine Pollendaten verfügbar",
                        message: "Für den aktuellen Zeitraum liegen keine Pollendaten vor."
                    )
                }
            } else {
                EnvironmentDetailCard {
                    EnvironmentDetailHeaderView(
                        title: "Pollen",
                        value: dominantPollen?.label ?? "--",
                        badge: dominantPollen.map { LocalizedStringKey($0.tierLabel) } ?? "Keine Daten",
                        color: dominantPollenSeverityColor,
                        subtitle: nil
                    )

                    PollenChart(
                        time: time,
                        alder: alder,
                        birch: birch,
                        grass: grass,
                        mugwort: mugwort,
                        ragweed: ragweed,
                        maxTimeRange: maxTimeRange,
                        referenceDate: referenceDate
                    )
                    .chartScrollPosition(x: $chartScrollPosition)
                }

                EnvironmentDetailCard {
                    Text("Aktuelle Werte")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    ForEach(Array(currentPollen.enumerated()), id: \.element.id) { index, pollen in
                        if index > 0 {
                            Divider().overlay(.white.opacity(0.08))
                        }

                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(Int(pollen.value))")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(pollen.color)

                                Text("Pollen/m³")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: pollen.label)
                                Text(LocalizedStringKey(pollen.tierLabel))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
