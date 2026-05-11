import Charts
import SwiftUI

struct DailyEnsembleWindChart: View {
  let points: [DailyEnsembleDayPoint]
  let unit: String

  @State private var selectedDate: Date?
  @State private var chartScrollPosition = Date.now

  private var domain: ClosedRange<Date> {
    guard let start = points.first?.date, let end = points.last?.date else {
      return Date.now...Date.now.addingTimeInterval(86_400)
    }
    return start...end
  }

  private var visibleDomainLength: TimeInterval {
    7 * 86_400
  }

  var body: some View {
    chart
      .chartXAxis {
        AxisMarks(values: points.map(\.date)) { _ in
          AxisValueLabel(format: .dateTime.weekday(.narrow).day())
          AxisGridLine()
          AxisTick()
        }
      }
      .chartXScale(domain: domain)
      .chartXSelection(value: $selectedDate)
      .scrollingIfNeeded(
        points.count > 8,
        visibleDomainLength: visibleDomainLength,
        scrollPosition: $chartScrollPosition
      )
      .frame(height: 240)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        legend
      }
      .onAppear(perform: resetScrollPosition)
      .onChange(of: points.first?.date) { _, _ in
        resetScrollPosition()
      }
      .onChange(of: points.count) { _, _ in
        resetScrollPosition()
      }
  }

  private var chart: some View {
    Chart {
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
              valueRow(color: .cyan, label: "Min", value: selectedPoint.windSpeedMin)
              rangeRow(
                color: .cyan.opacity(0.55),
                label: "Min-Band",
                low: selectedPoint.windSpeedMinMemberLow,
                high: selectedPoint.windSpeedMinMemberHigh
              )
              valueRow(color: .blue, label: "Max", value: selectedPoint.windSpeedMax)
              rangeRow(
                color: .blue.opacity(0.55),
                label: "Max-Band",
                low: selectedPoint.windSpeedMaxMemberLow,
                high: selectedPoint.windSpeedMaxMemberHigh
              )
            }
            .padding(8)
            .background(.ultraThinMaterial.opacity(0.9))
            .clipShape(.rect(cornerRadius: 8))
            .shadow(radius: 4)
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

  private func selectedPoint(for date: Date) -> DailyEnsembleDayPoint? {
    points.min { first, second in
      abs(first.date.timeIntervalSince(date)) < abs(second.date.timeIntervalSince(date))
    }
  }

  private func resetScrollPosition() {
    if let firstDate = points.first?.date {
      chartScrollPosition = firstDate
    }
  }

  private func valueRow(color: Color, label: LocalizedStringKey, value: Double?) -> some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 6, height: 6)
      (Text(label) + Text(": \(formatted(value))"))
        .font(.caption2)
        .foregroundStyle(.white)
    }
  }

  private func rangeRow(color: Color, label: LocalizedStringKey, low: Double?, high: Double?) -> some View {
    HStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 2)
        .fill(color)
        .frame(width: 10, height: 6)
      (Text(label) + Text(": \(formatted(low)) - \(formatted(high))"))
        .font(.caption2)
        .foregroundStyle(.white)
    }
  }

  private var legend: some View {
    HStack(spacing: 12) {
      legendItem(color: .cyan, label: "Minimum")
      legendItem(color: .cyan.opacity(0.35), label: "Min-Band")
      legendItem(color: .blue, label: "Maximum")
      legendItem(color: .blue.opacity(0.35), label: "Max-Band")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 6)
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

  private func formatted(_ value: Double?) -> String {
    WindSpeedFormatter.string(value, unit: unit)
  }

  private func invertWindDirection(_ degrees: Double) -> Double {
    (degrees + 180).truncatingRemainder(dividingBy: 360)
  }
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
