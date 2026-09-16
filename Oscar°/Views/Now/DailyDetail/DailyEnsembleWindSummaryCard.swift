import SwiftUI

struct DailyEnsembleWindSummaryCard: View {
  let points: [DailyEnsembleDayPoint]
  let unit: String

  var body: some View {
    let windiest = points.max { ($0.windSpeedMax ?? -1) < ($1.windSpeedMax ?? -1) }
    let calmest = points.min { ($0.windSpeedMin ?? 999) < ($1.windSpeedMin ?? 999) }
    let fuzziestMax = points.widestSpan(high: \.windSpeedMaxMemberHigh, low: \.windSpeedMaxMemberLow)
    let fuzziestMin = points.widestSpan(high: \.windSpeedMinMemberHigh, low: \.windSpeedMinMemberLow)
    DailyEnsembleSummaryCard(stats: [
      DailyEnsembleStat(
        label: "Windigster Tag",
        value: formatted(windiest?.windSpeedMax),
        valueColor: .blue,
        date: windiest?.date.ensembleShortDate
      ),
      DailyEnsembleStat(
        label: "Ruhigster Tag",
        value: formatted(calmest?.windSpeedMin),
        valueColor: .cyan,
        date: calmest?.date.ensembleShortDate
      ),
      DailyEnsembleStat(
        label: "Unsicherster Tag",
        subtitle: "Windböen",
        value: fuzziestMax.map { "±" + formatted($0.span / 2) } ?? "--",
        valueColor: .orange,
        date: fuzziestMax?.point.date.ensembleShortDate
      ),
      DailyEnsembleStat(
        label: "Unsicherster Tag",
        subtitle: "Windstillen",
        value: fuzziestMin.map { "±" + formatted($0.span / 2) } ?? "--",
        valueColor: .orange,
        date: fuzziestMin?.point.date.ensembleShortDate
      ),
      DailyEnsembleStat(
        label: "Ø Bandbreite",
        subtitle: "Windböen",
        value: formatted(points.averageSpan(high: \.windSpeedMaxMemberHigh, low: \.windSpeedMaxMemberLow)),
        valueColor: .secondary
      ),
      DailyEnsembleStat(
        label: "Ø Bandbreite",
        subtitle: "Windstillen",
        value: formatted(points.averageSpan(high: \.windSpeedMinMemberHigh, low: \.windSpeedMinMemberLow)),
        valueColor: .secondary
      ),
    ])
  }

  private func formatted(_ value: Double?) -> String {
    WindSpeedFormatter.string(value, unit: unit)
  }
}
