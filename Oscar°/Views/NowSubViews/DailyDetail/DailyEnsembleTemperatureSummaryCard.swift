import SwiftUI

struct DailyEnsembleTemperatureSummaryCard: View {
  let points: [DailyEnsembleDayPoint]
  let unit: String

  private var hottestDay: DailyEnsembleDayPoint? {
    points.max { ($0.temperatureMax ?? -999) < ($1.temperatureMax ?? -999) }
  }

  private var coldestDay: DailyEnsembleDayPoint? {
    points.min { ($0.temperatureMin ?? 999) < ($1.temperatureMin ?? 999) }
  }

  private var fuzziestMaxDay: (point: DailyEnsembleDayPoint, span: Double)? {
    points.compactMap { point -> (DailyEnsembleDayPoint, Double)? in
      guard let high = point.temperatureMaxMemberHigh,
            let low = point.temperatureMaxMemberLow else { return nil }
      return (point, high - low)
    }.max { $0.1 < $1.1 }
  }

  private var fuzziestMinDay: (point: DailyEnsembleDayPoint, span: Double)? {
    points.compactMap { point -> (DailyEnsembleDayPoint, Double)? in
      guard let high = point.temperatureMinMemberHigh,
            let low = point.temperatureMinMemberLow else { return nil }
      return (point, high - low)
    }.max { $0.1 < $1.1 }
  }

  private var avgMaxSpan: Double? {
    let spans = points.compactMap { p -> Double? in
      guard let h = p.temperatureMaxMemberHigh, let l = p.temperatureMaxMemberLow else { return nil }
      return h - l
    }
    guard !spans.isEmpty else { return nil }
    return spans.reduce(0, +) / Double(spans.count)
  }

  private var avgMinSpan: Double? {
    let spans = points.compactMap { p -> Double? in
      guard let h = p.temperatureMinMemberHigh, let l = p.temperatureMinMemberLow else { return nil }
      return h - l
    }
    guard !spans.isEmpty else { return nil }
    return spans.reduce(0, +) / Double(spans.count)
  }

  var body: some View {
    EnvironmentDetailCard {
      Text("Nächsten Tage")
        .font(.headline)
        .foregroundStyle(.primary)

      statRow(
        label: "Wärmster Tag",
        subtitle: nil,
        value: formatted(hottestDay?.temperatureMax),
        valueColor: .red,
        date: hottestDay.map { shortDate($0.date) }
      )
      Divider().overlay(.white.opacity(0.08))
      statRow(
        label: "Kältester Tag",
        subtitle: nil,
        value: formatted(coldestDay?.temperatureMin),
        valueColor: .blue,
        date: coldestDay.map { shortDate($0.date) }
      )
      Divider().overlay(.white.opacity(0.08))
      statRow(
        label: "Unsicherster Tag",
        subtitle: "Tageshöchstwerte",
        value: fuzziestMaxDay.map { "±\(String(format: "%.1f", $0.span / 2)) \(unit)" } ?? "--",
        valueColor: .orange,
        date: fuzziestMaxDay.map { shortDate($0.point.date) }
      )
      Divider().overlay(.white.opacity(0.08))
      statRow(
        label: "Unsicherster Tag",
        subtitle: "Tagestiefwerte",
        value: fuzziestMinDay.map { "±\(String(format: "%.1f", $0.span / 2)) \(unit)" } ?? "--",
        valueColor: .cyan,
        date: fuzziestMinDay.map { shortDate($0.point.date) }
      )
      Divider().overlay(.white.opacity(0.08))
      statRow(
        label: "Ø Bandbreite",
        subtitle: "Tageshöchstwerte",
        value: avgMaxSpan.map { "\(String(format: "%.1f", $0)) \(unit)" } ?? "--",
        valueColor: .secondary,
        date: nil
      )
      Divider().overlay(.white.opacity(0.08))
      statRow(
        label: "Ø Bandbreite",
        subtitle: "Tagestiefwerte",
        value: avgMinSpan.map { "\(String(format: "%.1f", $0)) \(unit)" } ?? "--",
        valueColor: .secondary,
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
