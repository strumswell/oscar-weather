import SwiftUI

struct DailyEnsemblePrecipitationSummaryCard: View {
  let points: [DailyEnsembleDayPoint]
  let unit: String

  private var wettestDay: DailyEnsembleDayPoint? {
    points.max { ($0.precipitationSum ?? -1) < ($1.precipitationSum ?? -1) }
  }

  private var driestDay: DailyEnsembleDayPoint? {
    points.min { ($0.precipitationSum ?? 999) < ($1.precipitationSum ?? 999) }
  }

  private var highestUncertaintyDay: (point: DailyEnsembleDayPoint, span: Double)? {
    points.compactMap { point -> (DailyEnsembleDayPoint, Double)? in
      guard let high = point.precipitationSumMemberHigh,
            let low = point.precipitationSumMemberLow else { return nil }
      return (point, high - low)
    }.max { $0.1 < $1.1 }
  }

  private var avgUncertainty: Double? {
    let spans = points.compactMap { p -> Double? in
      guard let h = p.precipitationSumMemberHigh, let l = p.precipitationSumMemberLow else { return nil }
      return h - l
    }
    guard !spans.isEmpty else { return nil }
    return spans.reduce(0, +) / Double(spans.count)
  }

  private var totalPrecipitation: Double? {
    let values = points.compactMap(\.precipitationSum)
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +)
  }

  var body: some View {
    EnvironmentDetailCard {
      Text("Nächsten Tage")
        .font(.headline)
        .foregroundStyle(.primary)

      statRow(
        label: "Stärkster Tag",
        subtitle: nil,
        value: formatted(wettestDay?.precipitationSum),
        valueColor: .blue,
        date: wettestDay.map { shortDate($0.date) }
      )
      Divider().overlay(.white.opacity(0.08))
      statRow(
        label: "Trockenster Tag",
        subtitle: nil,
        value: formatted(driestDay?.precipitationSum),
        valueColor: .yellow,
        date: driestDay.map { shortDate($0.date) }
      )
      Divider().overlay(.white.opacity(0.08))
      statRow(
        label: "Unsicherster Tag",
        subtitle: nil,
        value: highestUncertaintyDay.map { "±\(String(format: "%.1f", $0.span / 2)) \(unit)" } ?? "--",
        valueColor: .orange,
        date: highestUncertaintyDay.map { shortDate($0.point.date) }
      )
      Divider().overlay(.white.opacity(0.08))
      statRow(
        label: "Ø Ensemble-Unsicherheit",
        subtitle: nil,
        value: avgUncertainty.map { "\(String(format: "%.1f", $0)) \(unit)" } ?? "--",
        valueColor: .secondary,
        date: nil
      )
      Divider().overlay(.white.opacity(0.08))
      statRow(
        label: "Gesamtniederschlag",
        subtitle: nil,
        value: totalPrecipitation.map { "\(String(format: "%.1f", $0)) \(unit)" } ?? "--",
        valueColor: .blue,
        date: nil
      )
    }
  }

  private func formatted(_ value: Double?) -> String {
    guard let value else { return "--" }
    return "\(String(format: "%.1f", value)) \(unit)"
  }

  private func shortDate(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
  }

  private func statRow(label: LocalizedStringKey, subtitle: LocalizedStringKey?, value: String, valueColor: Color, date: String?) -> some View {
    LabeledContent {
      VStack(alignment: .trailing, spacing: 2) {
        Text(value)
          .fontWeight(.semibold)
          .foregroundStyle(valueColor)
        if let date {
          Text(date)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
