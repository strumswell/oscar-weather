import Charts
import SwiftUI

struct DailyEnsemblePrecipitationSumChart: View {
  let points: [DailyEnsembleDayPoint]
  let unit: String

  @State private var selectedDate: Date?
  @State private var chartScrollPosition = Date.now

  var body: some View {
    DailyEnsemblePrecipitationChartContainer(
      points: points,
      selectedDate: $selectedDate,
      chartScrollPosition: $chartScrollPosition,
      yUpperBound: yUpperBound,
      legend: {
        HStack(spacing: 12) {
          legendItem(color: .blue, label: "Ø Summe")
          legendItem(color: .blue.opacity(0.35), label: "Band")
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

      selectionAnnotation
    }
    .frame(height: 230)
    .onAppear(perform: resetScrollPosition)
    .onChange(of: points.first?.date) { _, _ in
      resetScrollPosition()
    }
    .onChange(of: points.count) { _, _ in
      resetScrollPosition()
    }
  }

  @ChartContentBuilder
  private var selectionAnnotation: some ChartContent {
    if let selectedDate, let selectedPoint = selectedPoint(for: selectedDate) {
      RuleMark(x: .value("Auswahl", selectedDate))
        .foregroundStyle(.gray.opacity(0.3))
        .lineStyle(.init(lineWidth: 2))
        .annotation(
          position: .topTrailing,
          overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
        ) {
          VStack(alignment: .leading, spacing: 4) {
            Text(selectedPoint.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
              .font(.caption)
              .foregroundStyle(.secondary)
            valueRow(color: .blue, label: "Ø Summe", value: selectedPoint.precipitationSum, unit: unit)
            rangeRow(
              color: .blue.opacity(0.55),
              label: "Band",
              low: selectedPoint.precipitationSumMemberLow,
              high: selectedPoint.precipitationSumMemberHigh,
              unit: unit
            )
          }
          .padding(8)
          .background(.ultraThinMaterial.opacity(0.9))
          .clipShape(.rect(cornerRadius: 8))
          .shadow(radius: 4)
        }
    }
  }

  private var yUpperBound: Double {
    let values = points.flatMap { [$0.precipitationSum, $0.precipitationSumMemberHigh] }
      .compactMap { $0 }
    return max((values.max() ?? 1) * 1.18, 1)
  }

  private func selectedPoint(for date: Date) -> DailyEnsembleDayPoint? {
    points.min { first, second in
      abs(first.date.timeIntervalSince(date)) < abs(second.date.timeIntervalSince(date))
    }
  }

  private func barStart(for date: Date) -> Date {
    date.addingTimeInterval(-0.28 * 86_400)
  }

  private func barEnd(for date: Date) -> Date {
    date.addingTimeInterval(0.28 * 86_400)
  }

  private func resetScrollPosition() {
    if let firstDate = points.first?.date {
      chartScrollPosition = firstDate
    }
  }
}

private struct DailyEnsemblePrecipitationChartContainer<Content: ChartContent, Legend: View>: View {
  let points: [DailyEnsembleDayPoint]
  @Binding var selectedDate: Date?
  @Binding var chartScrollPosition: Date
  let yUpperBound: Double
  let legend: Legend
  let content: Content

  init(
    points: [DailyEnsembleDayPoint],
    selectedDate: Binding<Date?>,
    chartScrollPosition: Binding<Date>,
    yUpperBound: Double,
    @ViewBuilder legend: () -> Legend,
    @ChartContentBuilder content: () -> Content
  ) {
    self.points = points
    self._selectedDate = selectedDate
    self._chartScrollPosition = chartScrollPosition
    self.yUpperBound = yUpperBound
    self.legend = legend()
    self.content = content()
  }

  var body: some View {
    Chart {
      content
    }
    .chartXAxis {
      AxisMarks(values: points.map(\.date)) { _ in
        AxisValueLabel(format: .dateTime.weekday(.narrow).day())
        AxisGridLine()
        AxisTick()
      }
    }
    .chartXScale(domain: domain)
    .chartYScale(domain: 0...max(yUpperBound, 1))
    .chartXSelection(value: $selectedDate)
    .scrollingIfNeeded(
      points.count > 8,
      visibleDomainLength: 7 * 86_400,
      scrollPosition: $chartScrollPosition
    )
    .safeAreaInset(edge: .bottom, spacing: 0) {
      legend
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
  }

  private var domain: ClosedRange<Date> {
    guard let start = points.first?.date, let end = points.last?.date else {
      return Date.now...Date.now.addingTimeInterval(86_400)
    }
    // Pad half a day on each side so the first/last bars (which span ±0.28 day
    // around their date) stay fully inside the plot instead of clipping at the edges.
    return start.addingTimeInterval(-0.5 * 86_400)...end.addingTimeInterval(0.5 * 86_400)
  }
}

private func valueRow(color: Color, label: LocalizedStringKey, value: Double?, unit: String) -> some View {
  HStack(spacing: 4) {
    Circle()
      .fill(color)
      .frame(width: 6, height: 6)
    (Text(label) + Text(": \(formatted(value, unit: unit))"))
      .font(.caption2)
      .foregroundStyle(.white)
  }
}

private func rangeRow(
  color: Color,
  label: LocalizedStringKey,
  low: Double?,
  high: Double?,
  unit: String
) -> some View {
  HStack(spacing: 4) {
    RoundedRectangle(cornerRadius: 2)
      .fill(color)
      .frame(width: 10, height: 6)
    (Text(label) + Text(": \(formatted(low, unit: unit)) - \(formatted(high, unit: unit))"))
      .font(.caption2)
      .foregroundStyle(.white)
  }
}

private func legendItem(color: Color, label: LocalizedStringKey) -> some View {
  HStack(spacing: 4) {
    Circle()
      .fill(color)
      .frame(width: 7, height: 7)
    Text(label)
      .font(.caption2)
      .foregroundStyle(.secondary)
  }
}

private func formatted(_ value: Double?, unit: String) -> String {
  guard let value else { return "--" }
  return "\(String(format: "%.1f", value)) \(unit)"
}

private extension View {
  @ViewBuilder
  func scrollingIfNeeded(
    _ shouldScroll: Bool,
    visibleDomainLength: TimeInterval,
    scrollPosition: Binding<Date>
  ) -> some View {
    if shouldScroll {
      self
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleDomainLength)
        .chartScrollPosition(x: scrollPosition)
    } else {
      self
    }
  }
}
