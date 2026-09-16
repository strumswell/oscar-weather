import SwiftUI

struct DailyEnsemblePrecipitationSummaryCard: View {
  let points: [DailyEnsembleDayPoint]
  let unit: String

  var body: some View {
    let wettest = points.max { ($0.precipitationSum ?? -1) < ($1.precipitationSum ?? -1) }
    let driest = points.min { ($0.precipitationSum ?? 999) < ($1.precipitationSum ?? 999) }
    let fuzziest = points.widestSpan(high: \.precipitationSumMemberHigh, low: \.precipitationSumMemberLow)
    let sums = points.compactMap(\.precipitationSum)
    DailyEnsembleSummaryCard(stats: [
      DailyEnsembleStat(
        label: "Stärkster Tag",
        value: formatted(wettest?.precipitationSum),
        valueColor: .blue,
        date: wettest?.date.ensembleShortDate
      ),
      DailyEnsembleStat(
        label: "Trockenster Tag",
        value: formatted(driest?.precipitationSum),
        valueColor: .yellow,
        date: driest?.date.ensembleShortDate
      ),
      DailyEnsembleStat(
        label: "Unsicherster Tag",
        value: fuzziest.map { "±" + formatted($0.span / 2) } ?? "--",
        valueColor: .orange,
        date: fuzziest?.point.date.ensembleShortDate
      ),
      DailyEnsembleStat(
        label: "Ø Ensemble-Unsicherheit",
        value: formatted(points.averageSpan(high: \.precipitationSumMemberHigh, low: \.precipitationSumMemberLow)),
        valueColor: .secondary
      ),
      DailyEnsembleStat(
        label: "Gesamtniederschlag",
        value: sums.isEmpty ? "--" : formatted(sums.reduce(0, +)),
        valueColor: .blue
      ),
    ])
  }

  private func formatted(_ value: Double?) -> String {
    DailyEnsembleFormat.value(value, unit: unit)
  }
}
