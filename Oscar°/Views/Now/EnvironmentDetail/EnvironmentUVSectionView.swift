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
    let initialChartScrollPosition: Date
    let chartScrollSynchronizer: ChartScrollSynchronizer
    let chartTimelineVersion: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EnvironmentDetailCard {
                EnvironmentDetailHeaderView(
                    title: "UV-Index",
                    value: currentUV.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "--",
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
                .synchronizedChartScroll(
                    initialX: initialChartScrollPosition,
                    using: chartScrollSynchronizer
                )
                .id(chartTimelineVersion)
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
