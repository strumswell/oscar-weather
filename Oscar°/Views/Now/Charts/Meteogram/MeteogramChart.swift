import Charts
import SwiftUI

/// Meteoblue-style meteogram: one merged hero canvas (daylight tint, cloud
/// layers at their altitude bands, temperature with inline daily extrema,
/// precipitation bars, weather-icon row) plus an aligned wind strip below
/// (line + gust envelope + direction arrows). Both charts share the time axis
/// via `ChartScrollSynchronizer` and one selection binding, so a scrub in
/// either runs a cursor through both. Y-axes are hidden — the canvas conveys
/// values through inline labels and the readout header; the wind strip keeps
/// inset min/max labels.
struct MeteogramChart: View {
  let model: MeteogramModel
  let zoom: MeteogramZoom
  let synchronizer: ChartScrollSynchronizer
  let initialScrollDate: Date

  /// Selection lives HERE, not on the page, and stores the snapped hour
  /// index: the binding below dedupes the continuous drag samples down to
  /// hour crossings, so a scrub re-renders only these two (already heavy)
  /// panels a few times per second instead of the whole page per sample —
  /// that per-sample invalidation was the tooltip lag. A zoom change
  /// recreates this view via `.id(zoom)`, which also resets the selection.
  @State private var selectedIndex: Int?

  private var selection: Binding<Date?> {
    Binding(
      get: {
        guard let selectedIndex, model.dates.indices.contains(selectedIndex) else { return nil }
        return model.dates[selectedIndex]
      },
      set: { newValue in
        guard let newValue else {
          selectedIndex = nil
          return
        }
        let snapped = model.snappedIndex(for: newValue)
        if snapped != selectedIndex {
          selectedIndex = snapped
          UIApplication.shared.playHapticFeedback()
        }
      }
    )
  }

  private var context: MeteogramPanelContext {
    MeteogramPanelContext(
      model: model,
      zoom: zoom,
      selectedIndex: selectedIndex,
      synchronizer: synchronizer,
      initialScrollDate: initialScrollDate
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      MeteogramCanvas(context: context, selection: selection)
      MeteogramWindStrip(context: context, selection: selection)
    }
  }
}

// MARK: - Shared panel plumbing

struct MeteogramPanelContext {
  let model: MeteogramModel
  let zoom: MeteogramZoom
  let selectedIndex: Int?
  let synchronizer: ChartScrollSynchronizer
  let initialScrollDate: Date

  var selectedDate: Date? {
    guard let selectedIndex, model.dates.indices.contains(selectedIndex) else { return nil }
    return model.dates[selectedIndex]
  }
}

extension View {
  /// Scroll/zoom/selection configuration shared by both charts.
  func meteogramPanelBase(
    _ context: MeteogramPanelContext, selection: Binding<Date?>
  ) -> some View {
    chartXScale(domain: context.model.fullRange)
      .chartYAxis(.hidden)
      .chartScrollableAxes(.horizontal)
      .chartXVisibleDomain(length: context.zoom.seconds)
      .chartXSelection(value: selection)
      .synchronizedChartScroll(
        initialX: context.initialScrollDate, using: context.synchronizer)
  }

  /// Gridline-only time axis (the hero canvas).
  func meteogramGridAxis(_ context: MeteogramPanelContext) -> some View {
    chartXAxis {
      AxisMarks(values: context.model.axisDates(for: context.zoom)) { _ in
        AxisGridLine()
          .foregroundStyle(.white.opacity(0.08))
      }
    }
  }

  /// Labeled time axis for the bottom chart: hours, with the weekday taking
  /// over at midnight ("DO 23" instead of "00 Uhr"), meteoblue-style.
  func meteogramLabeledAxis(_ context: MeteogramPanelContext) -> some View {
    chartXAxis {
      AxisMarks(values: context.model.axisDates(for: context.zoom)) { value in
        AxisGridLine()
          .foregroundStyle(.white.opacity(0.08))
        AxisTick()
        AxisValueLabel {
          if let date = value.as(Date.self) {
            meteogramAxisLabel(for: date, zoom: context.zoom)
          }
        }
      }
    }
  }
}

@ViewBuilder
private func meteogramAxisLabel(for date: Date, zoom: MeteogramZoom) -> some View {
  let isMidnight = Calendar.current.component(.hour, from: date) == 0
  if isMidnight, zoom == .days14 {
    Text(date.formatted(.dateTime.weekday(.narrow)))
      .fontWeight(.medium)
  }
  if isMidnight, zoom == .days7 {
    Text(HourlyChartUtilities.dayAbbreviation(from: date))
      .fontWeight(.medium)
  }
  if isMidnight, zoom != .days7, zoom != .days14 {
    Text(
      HourlyChartUtilities.dayAbbreviation(from: date) + " "
        + date.formatted(.dateTime.day())
    )
    .fontWeight(.medium)
  }
  if !isMidnight, zoom.hourAxisStride != nil {
    Text(HourlyChartUtilities.hourString(from: date))
  }
}

@ChartContentBuilder
func meteogramDayRules(_ context: MeteogramPanelContext) -> some ChartContent {
  ForEach(context.model.dayBoundaries) { boundary in
    RuleMark(x: .value("Hour", boundary.date))
      .foregroundStyle(.gray.opacity(0.4))
      .lineStyle(StrokeStyle(lineWidth: 1, dash: [8, 4]))
  }
}

@ChartContentBuilder
func meteogramNowRule(_ context: MeteogramPanelContext) -> some ChartContent {
  RuleMark(x: .value("Jetzt", context.model.referenceDate))
    .foregroundStyle(.white.opacity(0.18))
    .lineStyle(.init(lineWidth: 1))
}

@ChartContentBuilder
func meteogramSelectionRule(at date: Date) -> some ChartContent {
  RuleMark(x: .value("Selected", date))
    .foregroundStyle(.white.opacity(0.35))
    .lineStyle(.init(lineWidth: 1.5))
}

@ChartContentBuilder
func meteogramDotPair(date: Date, value: Double, series: String) -> some ChartContent {
  PointMark(x: .value("Hour", date), y: .value(series, value))
    .symbol(.circle)
    .symbolSize(90)
    .foregroundStyle(.black)
  PointMark(x: .value("Hour", date), y: .value(series, value))
    .symbol(.circle)
    .symbolSize(42)
    .foregroundStyle(.white)
}
