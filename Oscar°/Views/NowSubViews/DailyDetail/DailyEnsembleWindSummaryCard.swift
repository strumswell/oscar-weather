import SwiftUI

struct DailyEnsembleWindSummaryCard: View {
  let points: [DailyEnsembleDayPoint]
  let unit: String

  private var windiestDay: DailyEnsembleDayPoint? {
    points.max { ($0.windSpeedMax ?? -1) < ($1.windSpeedMax ?? -1) }
  }

  private var calmestDay: DailyEnsembleDayPoint? {
    points.min { ($0.windSpeedMin ?? 999) < ($1.windSpeedMin ?? 999) }
  }

  private var fuzziestMaxDay: (point: DailyEnsembleDayPoint, span: Double)? {
    points.compactMap { point -> (DailyEnsembleDayPoint, Double)? in
      guard let high = point.windSpeedMaxMemberHigh,
            let low = point.windSpeedMaxMemberLow else { return nil }
      return (point, high - low)
    }.max { $0.1 < $1.1 }
  }

  private var fuzziestMinDay: (point: DailyEnsembleDayPoint, span: Double)? {
    points.compactMap { point -> (DailyEnsembleDayPoint, Double)? in
      guard let high = point.windSpeedMinMemberHigh,
            let low = point.windSpeedMinMemberLow else { return nil }
      return (point, high - low)
    }.max { $0.1 < $1.1 }
  }

  private var avgMaxSpan: Double? {
    let spans = points.compactMap { p -> Double? in
      guard let h = p.windSpeedMaxMemberHigh, let l = p.windSpeedMaxMemberLow else { return nil }
      return h - l
    }
    guard !spans.isEmpty else { return nil }
    return spans.reduce(0, +) / Double(spans.count)
  }

  private var avgMinSpan: Double? {
    let spans = points.compactMap { p -> Double? in
      guard let h = p.windSpeedMinMemberHigh, let l = p.windSpeedMinMemberLow else { return nil }
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
        label: "Windigster Tag",
        subtitle: nil,
        value: formatted(windiestDay?.windSpeedMax),
        valueColor: .blue,
        date: windiestDay.map { shortDate($0.date) }
      )
      Divider().overlay(.white.opacity(0.08))
      statRow(
        label: "Ruhigster Tag",
        subtitle: nil,
        value: formatted(calmestDay?.windSpeedMin),
        valueColor: .cyan,
        date: calmestDay.map { shortDate($0.date) }
      )
      Divider().overlay(.white.opacity(0.08))
      statRow(
        label: "Unsicherster Tag",
        subtitle: "Windböen",
        value: fuzziestMaxDay.map { "±\(String(format: "%.1f", $0.span / 2)) \(unit)" } ?? "--",
        valueColor: .orange,
        date: fuzziestMaxDay.map { shortDate($0.point.date) }
      )
      Divider().overlay(.white.opacity(0.08))
      statRow(
        label: "Unsicherster Tag",
        subtitle: "Windstillen",
        value: fuzziestMinDay.map { "±\(String(format: "%.1f", $0.span / 2)) \(unit)" } ?? "--",
        valueColor: .orange,
        date: fuzziestMinDay.map { shortDate($0.point.date) }
      )
      Divider().overlay(.white.opacity(0.08))
      statRow(
        label: "Ø Bandbreite",
        subtitle: "Windböen",
        value: avgMaxSpan.map { "\(String(format: "%.1f", $0)) \(unit)" } ?? "--",
        valueColor: .secondary,
        date: nil
      )
      Divider().overlay(.white.opacity(0.08))
      statRow(
        label: "Ø Bandbreite",
        subtitle: "Windstillen",
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
