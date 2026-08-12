import Charts
import SwiftUI

struct DailyEnsembleTemperatureChart: View {
  let points: [DailyEnsembleDayPoint]
  let unit: String

  @State private var selectedDate: Date?
  @State private var chartScrollPosition = Date.now

  /// One inline number on the chart: a day's mean max/min (bold, full color)
  /// or a band edge (smaller, dimmed).
  private struct DayValueLabel: Identifiable {
    enum Tier {
      case mean
      case band
    }

    let id: String
    let date: Date
    let anchorValue: Double
    let text: String
    let color: Color
    let tier: Tier
    let position: AnnotationPosition
  }

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
      .frame(height: 220)
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
        if let low = point.temperatureMinMemberLow, let high = point.temperatureMinMemberHigh {
          AreaMark(
            x: .value("Tag", point.date),
            yStart: .value("Min Unsicherheit unten", low),
            yEnd: .value("Min Unsicherheit oben", high),
            series: .value("Series", "min-band")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.blue.opacity(0.16))
        }
      }

      ForEach(points) { point in
        if let low = point.temperatureMinMemberLow, let high = point.temperatureMinMemberHigh {
          LineMark(
            x: .value("Tag", point.date),
            y: .value("Min Untergrenze", low),
            series: .value("Series", "min-low")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.blue.opacity(0.35))
          .lineStyle(.init(lineWidth: 1.5, dash: [5, 4]))

          LineMark(
            x: .value("Tag", point.date),
            y: .value("Min Obergrenze", high),
            series: .value("Series", "min-high")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.blue.opacity(0.35))
          .lineStyle(.init(lineWidth: 1.5, dash: [5, 4]))
        }
      }
      
      ForEach(points) { point in
        if let low = point.temperatureMaxMemberLow, let high = point.temperatureMaxMemberHigh {
          AreaMark(
            x: .value("Tag", point.date),
            yStart: .value("Max Unsicherheit unten", low),
            yEnd: .value("Max Unsicherheit oben", high),
            series: .value("Series", "max-band")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.red.opacity(0.16))
        }
      }

      ForEach(points) { point in
        if let low = point.temperatureMaxMemberLow, let high = point.temperatureMaxMemberHigh {
          LineMark(
            x: .value("Tag", point.date),
            y: .value("Max Untergrenze", low),
            series: .value("Series", "max-low")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.red.opacity(0.35))
          .lineStyle(.init(lineWidth: 1.5, dash: [5, 4]))

          LineMark(
            x: .value("Tag", point.date),
            y: .value("Max Obergrenze", high),
            series: .value("Series", "max-high")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.red.opacity(0.35))
          .lineStyle(.init(lineWidth: 1.5, dash: [5, 4]))
        }
      }

      ForEach(points) { point in
        if let temperatureMin = point.temperatureMin {
          LineMark(
            x: .value("Tag", point.date),
            y: .value("Minimum (\(unit))", temperatureMin),
            series: .value("Series", "minimum")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.blue)
          .lineStyle(.init(lineWidth: 3))
        }
      }

      ForEach(points) { point in
        if let temperatureMax = point.temperatureMax {
          LineMark(
            x: .value("Tag", point.date),
            y: .value("Maximum (\(unit))", temperatureMax),
            series: .value("Series", "maximum")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.red)
          .lineStyle(.init(lineWidth: 3))
        }
      }

      ForEach(dayValueLabels) { label in
        PointMark(
          x: .value("Tag", label.date),
          y: .value("Wert", label.anchorValue)
        )
        .opacity(0)
        .annotation(
          position: label.position, spacing: 2,
          overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
        ) {
          Text(label.text)
            .font(label.tier == .mean ? .footnote.weight(.bold) : .caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(label.color)
            .shadow(color: .black.opacity(0.35), radius: 2)
        }
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
              valueRow(color: .blue, label: "Ø Min", value: selectedPoint.temperatureMin)
              rangeRow(
                color: .blue.opacity(0.55),
                label: "Min-Band",
                low: selectedPoint.temperatureMinMemberLow,
                high: selectedPoint.temperatureMinMemberHigh
              )
              valueRow(color: .red, label: "Ø Max", value: selectedPoint.temperatureMax)
              rangeRow(
                color: .red.opacity(0.55),
                label: "Max-Band",
                low: selectedPoint.temperatureMaxMemberLow,
                high: selectedPoint.temperatureMaxMemberHigh
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

  /// The per-day inline numbers: mean max/min always, band edges only where
  /// they have room. "Room" is measured in data units equivalent to ~14pt of
  /// label height (approximating the auto y-domain against the plot height),
  /// so labels never stack: a band edge must clear its own mean label, the
  /// two facing edges between the bands must clear each other, and an edge
  /// facing the OTHER series' mean (possible when bands overlap) is dropped.
  private var dayValueLabels: [DayValueLabel] {
    let tops = points.compactMap { $0.temperatureMaxMemberHigh ?? $0.temperatureMax }
    let bottoms = points.compactMap { $0.temperatureMinMemberLow ?? $0.temperatureMin }
    guard let top = tops.max(), let bottom = bottoms.min() else { return [] }
    let gap = max(top - bottom, 1) * 14 / 185

    var labels: [DayValueLabel] = []
    for point in points {
      let day = "\(point.date.timeIntervalSince1970)"
      let max = point.temperatureMax
      let min = point.temperatureMin
      let maxHigh = point.temperatureMaxMemberHigh
      let maxLow = point.temperatureMaxMemberLow
      let minHigh = point.temperatureMinMemberHigh
      let minLow = point.temperatureMinMemberLow

      func add(_ suffix: String, _ value: Double, _ color: Color, _ tier: DayValueLabel.Tier, _ position: AnnotationPosition) {
        labels.append(DayValueLabel(
          id: "\(day)-\(suffix)",
          date: point.date,
          anchorValue: value,
          text: "\(Int(value.rounded()))°",
          color: color,
          tier: tier,
          position: position
        ))
      }

      if let max { add("max", max, .red, .mean, .top) }
      if let min { add("min", min, .blue, .mean, .bottom) }

      // The two band edges facing each other in the middle: both or neither.
      let middleClear: Bool = {
        guard let maxLow, let minHigh else { return true }
        return maxLow - minHigh >= 2.4 * gap
      }()

      if let max, let maxHigh, maxHigh - max >= gap {
        add("maxHigh", maxHigh, .red.opacity(0.7), .band, .top)
      }
      if let max, let maxLow, max - maxLow >= gap, middleClear,
         min.map({ maxLow - $0 >= 1.2 * gap }) ?? true {
        add("maxLow", maxLow, .red.opacity(0.7), .band, .bottom)
      }
      if let min, let minHigh, minHigh - min >= gap, middleClear,
         max.map({ $0 - minHigh >= 1.2 * gap }) ?? true {
        add("minHigh", minHigh, .blue.opacity(0.7), .band, .top)
      }
      if let min, let minLow, min - minLow >= gap {
        add("minLow", minLow, .blue.opacity(0.7), .band, .bottom)
      }
    }
    return labels
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
      legendItem(color: .blue, label: "Ø Min")
      legendItem(color: .blue.opacity(0.35), label: "Min-Band")
      legendItem(color: .red, label: "Ø Max")
      legendItem(color: .red.opacity(0.35), label: "Max-Band")
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
    guard let value else { return "--" }
    return "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
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
