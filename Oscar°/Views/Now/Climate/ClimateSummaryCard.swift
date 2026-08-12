import SwiftUI

struct ClimateSummaryCard: View {
    let summary: ClimateSummary
    let unit: ClimateTemperatureUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(climateHeadline(summary))
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let analog = climateAnalogLine(summary, unit) {
                Text(analog)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                WarmingStripesRibbon(stripes: summary.allStripes, sigma: summary.standardDeviation)
                ClimateTimeAxis(firstYear: summary.firstYear, todayYear: summary.todayYear)
            }
            .padding(.top, 2)

            HStack(spacing: 8) {
                Text("Heute \(summary.anomalyString(unit))")
                Spacer(minLength: 4)
                Text("Normal \(summary.normalString(unit))")
                Spacer(minLength: 4)
                Text("Rekord \(summary.previousWarmRecordString(unit)) (\(String(summary.previousWarmRecord.year)))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground()
        .clipShape(.rect(cornerRadius: 12))
        .cardBorder(RoundedRectangle(cornerRadius: 12))
    }
}
