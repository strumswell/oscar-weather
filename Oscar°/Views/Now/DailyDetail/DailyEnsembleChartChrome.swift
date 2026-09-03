import SwiftUI

/// The frosted tooltip at the selected day.
struct DailyEnsembleTooltip<Rows: View>: View {
  let date: Date
  @ViewBuilder let rows: Rows

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
        .font(.caption)
        .foregroundStyle(.secondary)
      rows
    }
    .padding(8)
    .background(.ultraThinMaterial.opacity(0.9))
    .clipShape(.rect(cornerRadius: 8))
    .shadow(radius: 4)
  }
}

struct DailyEnsembleValueRow: View {
  let color: Color
  let label: LocalizedStringKey
  let text: String

  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 6, height: 6)
      Text("\(Text(label)): \(text)")
        .font(.caption2)
        .foregroundStyle(.white)
    }
  }
}

struct DailyEnsembleRangeRow: View {
  let color: Color
  let label: LocalizedStringKey
  let low: String
  let high: String

  var body: some View {
    HStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 2)
        .fill(color)
        .frame(width: 10, height: 6)
      Text("\(Text(label)): \(low) - \(high)")
        .font(.caption2)
        .foregroundStyle(.white)
    }
  }
}

struct DailyEnsembleLegendItem: View {
  let color: Color
  let label: LocalizedStringKey

  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 7, height: 7)
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }
}

enum DailyEnsembleFormat {
  static func value(_ value: Double?, unit: String) -> String {
    guard let value else { return "--" }
    return "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
  }

  static func range(_ low: String, _ high: String) -> String {
    String(localized: "\(low) bis \(high)")
  }
}

extension Date {
  var ensembleShortDate: String {
    formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
  }
}

extension Array where Element == DailyEnsembleDayPoint {
  func nearest(to date: Date) -> DailyEnsembleDayPoint? {
    self.min { first, second in
      abs(first.date.timeIntervalSince(date)) < abs(second.date.timeIntervalSince(date))
    }
  }

  /// The day whose member band is widest, with the band's span.
  func widestSpan(
    high: KeyPath<DailyEnsembleDayPoint, Double?>,
    low: KeyPath<DailyEnsembleDayPoint, Double?>
  ) -> (point: DailyEnsembleDayPoint, span: Double)? {
    compactMap { point -> (point: DailyEnsembleDayPoint, span: Double)? in
      guard let top = point[keyPath: high], let bottom = point[keyPath: low] else { return nil }
      return (point, top - bottom)
    }.max { $0.span < $1.span }
  }

  func averageSpan(
    high: KeyPath<DailyEnsembleDayPoint, Double?>,
    low: KeyPath<DailyEnsembleDayPoint, Double?>
  ) -> Double? {
    let spans = compactMap { point -> Double? in
      guard let top = point[keyPath: high], let bottom = point[keyPath: low] else { return nil }
      return top - bottom
    }
    guard !spans.isEmpty else { return nil }
    return spans.reduce(0, +) / Double(spans.count)
  }
}
