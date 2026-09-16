import Charts
import SwiftUI

struct DailyEnsemblePrecipitationSumChart: View {
  let points: [DailyEnsembleDayPoint]
  let unit: String

  @State private var selectedDate: Date?

  var body: some View {
    DailyEnsembleChartShell(
      points: points,
      // Half a day on each side so the first/last bars (±0.28 day around
      // their date) stay fully inside the plot instead of clipping.
      selectedDate: $selectedDate,
      domainPadding: 0.5 * 86_400,
      yDomain: 0...max(yUpperBound, 1),
      height: 210,
      accessibilityLabel: "Niederschlagssummen Ensemble",
      accessibilityValue: accessibilitySummary,
      legend: {
        HStack(spacing: 12) {
          DailyEnsembleLegendItem(color: .blue, label: "Ø Summe")
          DailyEnsembleLegendItem(color: .blue.opacity(0.35), label: "Band")
        }
      }
    ) {
      ForEach(points) { point in
        if let low = point.precipitationSumMemberLow,
          let high = point.precipitationSumMemberHigh
        {
          AreaMark(
            x: .value("Tag", point.date),
            yStart: .value("Summen-Band unten", low),
            yEnd: .value("Summen-Band oben", high),
            series: .value("Series", "sum-band")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.blue.opacity(0.16))
        }
      }

      ForEach(points) { point in
        if let precipitationSum = point.precipitationSum {
          RectangleMark(
            xStart: .value("Tag Start", barStart(for: point.date)),
            xEnd: .value("Tag Ende", barEnd(for: point.date)),
            yStart: .value("Niederschlag Start", 0),
            yEnd: .value("Niederschlag (\(unit))", precipitationSum)
          )
          .foregroundStyle(.blue.opacity(0.82))
          .clipShape(.rect(cornerRadius: 4))
        }
      }

      ForEach(points) { point in
        if let low = point.precipitationSumMemberLow,
          let high = point.precipitationSumMemberHigh
        {
          LineMark(
            x: .value("Tag", point.date),
            y: .value("Summen-Band unten", low),
            series: .value("Series", "sum-low")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.blue.opacity(0.55))
          .lineStyle(.init(lineWidth: 1.5, dash: [5, 4]))

          LineMark(
            x: .value("Tag", point.date),
            y: .value("Summen-Band oben", high),
            series: .value("Series", "sum-high")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.blue.opacity(0.55))
          .lineStyle(.init(lineWidth: 1.5, dash: [5, 4]))
        }
      }

      if let selectedDate, let selectedPoint = points.nearest(to: selectedDate) {
        RuleMark(x: .value("Auswahl", selectedDate))
          .foregroundStyle(.gray.opacity(0.3))
          .lineStyle(.init(lineWidth: 2))
          .annotation(
            position: .topTrailing,
            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
          ) {
            DailyEnsembleTooltip(date: selectedPoint.date) {
              DailyEnsembleValueRow(color: .blue, label: "Ø Summe", text: formatted(selectedPoint.precipitationSum))
              DailyEnsembleRangeRow(
                color: .blue.opacity(0.55),
                label: "Band",
                low: formatted(selectedPoint.precipitationSumMemberLow),
                high: formatted(selectedPoint.precipitationSumMemberHigh)
              )
            }
          }
      }
    }
  }

  private var yUpperBound: Double {
    let values = points.flatMap { [$0.precipitationSum, $0.precipitationSumMemberHigh] }
      .compactMap { $0 }
    return max((values.max() ?? 1) * 1.18, 1)
  }

  private var accessibilitySummary: String {
    let sums = points.compactMap(\.precipitationSum)
    guard let wettest = points.max(by: { ($0.precipitationSum ?? -1) < ($1.precipitationSum ?? -1) }),
          !sums.isEmpty else { return "" }
    return String(localized: "Gesamt \(formatted(sums.reduce(0, +))), stärkster Tag \(formatted(wettest.precipitationSum)) am \(wettest.date.ensembleShortDate), \(points.count) Tage")
  }

  private func barStart(for date: Date) -> Date {
    date.addingTimeInterval(-0.28 * 86_400)
  }

  private func barEnd(for date: Date) -> Date {
    date.addingTimeInterval(0.28 * 86_400)
  }

  private func formatted(_ value: Double?) -> String {
    DailyEnsembleFormat.value(value, unit: unit)
  }
}
