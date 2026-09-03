import SwiftUI

struct DailyEnsembleTemperatureSummaryCard: View {
  let points: [DailyEnsembleDayPoint]
  let unit: String

  var body: some View {
    let hottest = points.max { ($0.temperatureMax ?? -999) < ($1.temperatureMax ?? -999) }
    let coldest = points.min { ($0.temperatureMin ?? 999) < ($1.temperatureMin ?? 999) }
    let fuzziestMax = points.widestSpan(high: \.temperatureMaxMemberHigh, low: \.temperatureMaxMemberLow)
    let fuzziestMin = points.widestSpan(high: \.temperatureMinMemberHigh, low: \.temperatureMinMemberLow)
    DailyEnsembleSummaryCard(stats: [
      DailyEnsembleStat(
        label: "Wärmster Tag",
        value: formatted(hottest?.temperatureMax),
        valueColor: .red,
        date: hottest?.date.ensembleShortDate
      ),
      DailyEnsembleStat(
        label: "Kältester Tag",
        value: formatted(coldest?.temperatureMin),
        valueColor: .blue,
        date: coldest?.date.ensembleShortDate
      ),
      DailyEnsembleStat(
        label: "Unsicherster Tag",
        subtitle: "Tageshöchstwerte",
        value: fuzziestMax.map { "±" + formatted($0.span / 2) } ?? "--",
        valueColor: .orange,
        date: fuzziestMax?.point.date.ensembleShortDate
      ),
      DailyEnsembleStat(
        label: "Unsicherster Tag",
        subtitle: "Tagestiefwerte",
        value: fuzziestMin.map { "±" + formatted($0.span / 2) } ?? "--",
        valueColor: .cyan,
        date: fuzziestMin?.point.date.ensembleShortDate
      ),
      DailyEnsembleStat(
        label: "Ø Bandbreite",
        subtitle: "Tageshöchstwerte",
        value: formatted(points.averageSpan(high: \.temperatureMaxMemberHigh, low: \.temperatureMaxMemberLow)),
        valueColor: .secondary
      ),
      DailyEnsembleStat(
        label: "Ø Bandbreite",
        subtitle: "Tagestiefwerte",
        value: formatted(points.averageSpan(high: \.temperatureMinMemberHigh, low: \.temperatureMinMemberLow)),
        valueColor: .secondary
      ),
    ])
  }

  private func formatted(_ value: Double?) -> String {
    DailyEnsembleFormat.value(value, unit: unit)
  }
}
