import SwiftUI

struct EnvironmentUVSectionView: View {
    let currentUV: Double?
    let currentUVBadge: LocalizedStringKey
    let currentUVColor: Color
    let riskTitle: String
    let riskBody: String
    let uvIndex: [Double]
    let time: [Double]
    let maxTimeRange: ClosedRange<Date>
    let referenceDate: Date
    @Binding var chartScrollPosition: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EnvironmentDetailCard {
                EnvironmentDetailHeaderView(
                    title: "UV-Index",
                    value: currentUV.map { String(format: "%.1f", $0) } ?? "--",
                    badge: currentUVBadge,
                    color: currentUVColor,
                    subtitle: nil
                )

                UVChart(
                    uvIndex: uvIndex,
                    time: time,
                    maxTimeRange: maxTimeRange,
                    referenceDate: referenceDate
                )
                .chartScrollPosition(x: $chartScrollPosition)
            }

            EnvironmentDetailCard {
                Text("Gesundheitsbewertung")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(LocalizedStringKey(riskTitle))
                    .font(.headline)
                    .foregroundStyle(currentUVColor)

                Text(LocalizedStringKey(riskBody))
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
    }
}
