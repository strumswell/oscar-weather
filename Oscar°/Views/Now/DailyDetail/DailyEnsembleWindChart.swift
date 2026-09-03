import Charts
import SwiftUI

struct DailyEnsembleWindChart: View {
  let points: [DailyEnsembleDayPoint]
  let unit: String

  @State private var selectedDate: Date?

  var body: some View {
    DailyEnsembleChartShell(
      points: points,
      selectedDate: $selectedDate,
      height: 240,
      accessibilityLabel: "Windverlauf Ensemble",
      accessibilityValue: accessibilitySummary,
      legend: {
        HStack(spacing: 12) {
          DailyEnsembleLegendItem(color: .cyan, label: "Ø Min")
          DailyEnsembleLegendItem(color: .cyan.opacity(0.35), label: "Min-Band")
          DailyEnsembleLegendItem(color: .blue, label: "Ø Max")
          DailyEnsembleLegendItem(color: .blue.opacity(0.35), label: "Max-Band")
        }
      }
    ) {
      ForEach(points) { point in
        if let low = point.windSpeedMinMemberLow, let high = point.windSpeedMinMemberHigh {
          AreaMark(
            x: .value("Tag", point.date),
            yStart: .value("Min Wind Untergrenze", low),
            yEnd: .value("Min Wind Obergrenze", high),
            series: .value("Series", "min-band")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.cyan.opacity(0.16))
        }
      }

      ForEach(points) { point in
        if let low = point.windSpeedMinMemberLow, let high = point.windSpeedMinMemberHigh {
          windBoundaryLine(point.date, low, color: .cyan.opacity(0.35), series: "min-low")
          windBoundaryLine(point.date, high, color: .cyan.opacity(0.35), series: "min-high")
        }
      }

      ForEach(points) { point in
        if let low = point.windSpeedMaxMemberLow, let high = point.windSpeedMaxMemberHigh {
          AreaMark(
            x: .value("Tag", point.date),
            yStart: .value("Max Wind Untergrenze", low),
            yEnd: .value("Max Wind Obergrenze", high),
            series: .value("Series", "max-band")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.blue.opacity(0.16))
        }
      }

      ForEach(points) { point in
        if let low = point.windSpeedMaxMemberLow, let high = point.windSpeedMaxMemberHigh {
          windBoundaryLine(point.date, low, color: .blue.opacity(0.35), series: "max-low")
          windBoundaryLine(point.date, high, color: .blue.opacity(0.35), series: "max-high")
        }
      }

      ForEach(points) { point in
        if let windSpeedMin = point.windSpeedMin {
          LineMark(
            x: .value("Tag", point.date),
            y: .value("Minimum (\(unit))", windSpeedMin),
            series: .value("Series", "minimum")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.cyan)
          .lineStyle(.init(lineWidth: 3))
        }
      }

      ForEach(points) { point in
        if let windSpeedMax = point.windSpeedMax {
          LineMark(
            x: .value("Tag", point.date),
            y: .value("Maximum (\(unit))", windSpeedMax),
            series: .value("Series", "maximum")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.blue)
          .lineStyle(.init(lineWidth: 3))
        }
      }

      ForEach(points) { point in
        directionPoint(point.date, point.windSpeedMin, point.windDirection, color: .cyan)
        directionPoint(point.date, point.windSpeedMax, point.windDirection, color: .blue)
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
              DailyEnsembleValueRow(color: .cyan, label: "Ø Min", text: formatted(selectedPoint.windSpeedMin))
              DailyEnsembleRangeRow(
                color: .cyan.opacity(0.55),
                label: "Min-Band",
                low: formatted(selectedPoint.windSpeedMinMemberLow),
                high: formatted(selectedPoint.windSpeedMinMemberHigh)
              )
              DailyEnsembleValueRow(color: .blue, label: "Ø Max", text: formatted(selectedPoint.windSpeedMax))
              DailyEnsembleRangeRow(
                color: .blue.opacity(0.55),
                label: "Max-Band",
                low: formatted(selectedPoint.windSpeedMaxMemberLow),
                high: formatted(selectedPoint.windSpeedMaxMemberHigh)
              )
            }
          }
      }
    }
  }

  @ChartContentBuilder
  private func windBoundaryLine(
    _ date: Date,
    _ speed: Double,
    color: Color,
    series: String
  ) -> some ChartContent {
    LineMark(
      x: .value("Tag", date),
      y: .value("Wind (\(unit))", speed),
      series: .value("Series", series)
    )
    .interpolationMethod(.catmullRom)
    .foregroundStyle(color)
    .lineStyle(.init(lineWidth: 1.5, dash: [5, 4]))
  }

  @ChartContentBuilder
  private func directionPoint(
    _ date: Date,
    _ speed: Double?,
    _ direction: Double?,
    color: Color
  ) -> some ChartContent {
    if let speed, let direction {
      PointMark(
        x: .value("Tag", date),
        y: .value("Wind (\(unit))", speed)
      )
      .symbol {
        Image(systemName: "location.north.fill")
          .resizable()
          .frame(width: 11, height: 11)
          .rotationEffect(.degrees(invertWindDirection(direction)))
          .foregroundStyle(color)
          .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
      }
    }
  }

  private var accessibilitySummary: String {
    guard let peak = points.compactMap(\.windSpeedMax).max(),
          let calm = points.compactMap(\.windSpeedMin).min() else { return "" }
    return String(localized: "Höchstwind bis \(formatted(peak)), Tiefstwind ab \(formatted(calm)), \(points.count) Tage")
  }

  private func formatted(_ value: Double?) -> String {
    WindSpeedFormatter.string(value, unit: unit)
  }

  private func invertWindDirection(_ degrees: Double) -> Double {
    (degrees + 180).truncatingRemainder(dividingBy: 360)
  }
}
