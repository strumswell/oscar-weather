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
  let selectedIndex: Int?
  let synchronizer: ChartScrollSynchronizer
  let initialScrollDate: Date
  @Binding var rawSelection: Date?

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
      MeteogramCanvas(context: context, rawSelection: $rawSelection)
      MeteogramWindStrip(context: context, rawSelection: $rawSelection)
    }
  }
}

// MARK: - Shared panel plumbing

private struct MeteogramPanelContext {
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
  fileprivate func meteogramPanelBase(
    _ context: MeteogramPanelContext, rawSelection: Binding<Date?>
  ) -> some View {
    chartXScale(domain: context.model.fullRange)
      .chartYAxis(.hidden)
      .chartScrollableAxes(.horizontal)
      .chartXVisibleDomain(length: context.zoom.seconds)
      .chartXSelection(value: rawSelection)
      .synchronizedChartScroll(
        initialX: context.initialScrollDate, using: context.synchronizer)
  }

  /// Gridline-only time axis (the hero canvas).
  fileprivate func meteogramGridAxis(_ context: MeteogramPanelContext) -> some View {
    chartXAxis {
      AxisMarks(values: context.model.axisDates(for: context.zoom)) { _ in
        AxisGridLine()
          .foregroundStyle(.white.opacity(0.08))
      }
    }
  }

  /// Labeled time axis for the bottom chart: hours, with the weekday taking
  /// over at midnight ("DO 23" instead of "00 Uhr"), meteoblue-style.
  fileprivate func meteogramLabeledAxis(_ context: MeteogramPanelContext) -> some View {
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
private func meteogramDayRules(_ context: MeteogramPanelContext) -> some ChartContent {
  ForEach(context.model.dayBoundaries) { boundary in
    RuleMark(x: .value("Hour", boundary.date))
      .foregroundStyle(.gray.opacity(0.4))
      .lineStyle(StrokeStyle(lineWidth: 1, dash: [8, 4]))
  }
}

@ChartContentBuilder
private func meteogramNowRule(_ context: MeteogramPanelContext) -> some ChartContent {
  RuleMark(x: .value("Jetzt", context.model.referenceDate))
    .foregroundStyle(.white.opacity(0.18))
    .lineStyle(.init(lineWidth: 1))
}

@ChartContentBuilder
private func meteogramSelectionRule(at date: Date) -> some ChartContent {
  RuleMark(x: .value("Selected", date))
    .foregroundStyle(.white.opacity(0.35))
    .lineStyle(.init(lineWidth: 1.5))
}

@ChartContentBuilder
private func meteogramDotPair(date: Date, value: Double, series: String) -> some ChartContent {
  PointMark(x: .value("Hour", date), y: .value(series, value))
    .symbol(.circle)
    .symbolSize(90)
    .foregroundStyle(.black)
  PointMark(x: .value("Hour", date), y: .value(series, value))
    .symbol(.circle)
    .symbolSize(42)
    .foregroundStyle(.white)
}

// MARK: - Hero canvas

private let meteogramCanvasHeight: CGFloat = 300

private func canvasY(_ unitY: Double) -> CGFloat {
  meteogramCanvasHeight * (1 - CGFloat(unitY))
}

private struct MeteogramCanvas: View {
  let context: MeteogramPanelContext
  @Binding var rawSelection: Date?

  var body: some View {
    Chart {
      backdropLayers
      iconRow
      temperatureLayers
      precipitationBars
      structureOverlays
    }
    .chartYScale(domain: 0...1)
    .meteogramGridAxis(context)
    .meteogramPanelBase(context, rawSelection: $rawSelection)
    .frame(height: meteogramCanvasHeight)
    .overlay(alignment: .topLeading) { leadingInsetLabels }
  }

  // Daylight/sunshine columns + cloud layers. Every AreaPlot carries a
  // distinct series — series-less AreaPlots would be merged into one stack.
  @ChartContentBuilder
  private var backdropLayers: some ChartContent {
    AreaPlot(
      context.model.canvasPoints,
      x: .value("Hour", \.date),
      yStart: .value("Base", \.zero),
      yEnd: .value("Tag", \.dayY),
      series: .value("Series", "daylight")
    )
    .interpolationMethod(.monotone)
    .foregroundStyle(.white.opacity(0.03))

    // Two stacked sunshine tiers: partly sunny gets one yellow wash, mostly
    // clear skies a second on top.
    AreaPlot(
      context.model.canvasPoints,
      x: .value("Hour", \.date),
      yStart: .value("Base", \.zero),
      yEnd: .value("Sonne", \.sunPartlyY),
      series: .value("Series", "sun-partly")
    )
    .interpolationMethod(.monotone)
    .foregroundStyle(.yellow.opacity(0.04))

    AreaPlot(
      context.model.canvasPoints,
      x: .value("Hour", \.date),
      yStart: .value("Base", \.zero),
      yEnd: .value("Sonne", \.sunFullY),
      series: .value("Series", "sun-full")
    )
    .interpolationMethod(.monotone)
    .foregroundStyle(.yellow.opacity(0.05))

    ForEach(context.model.cloudRibbons) { ribbon in
      AreaPlot(
        ribbon.band,
        x: .value("Hour", \.date),
        yStart: .value("Bewölkung", \.yStart),
        yEnd: .value("Bewölkung", \.yEnd),
        series: .value("Series", "cloud-\(ribbon.id)")
      )
      .interpolationMethod(.monotone)
      .foregroundStyle(.white.opacity(0.62))
    }
  }

  // MARK: In-chart altitude axis (static overlay, never scrolls)

  private var leadingInsetLabels: some View {
    ZStack(alignment: .topLeading) {
      insetLabel("> 8 km", unitY: MeteogramModel.CanvasZone.cloudCenterHigh)
      insetLabel("3–8 km", unitY: MeteogramModel.CanvasZone.cloudCenterMid)
      insetLabel("0–3 km", unitY: MeteogramModel.CanvasZone.cloudCenterLow)
      if let freezingY = context.model.freezingUnitY {
        Text(verbatim: context.model.freezingLabel)
          .font(.caption2)
          .monospacedDigit()
          .foregroundStyle(.cyan.opacity(0.9))
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(.ultraThinMaterial, in: .capsule)
          .offset(x: 4, y: canvasY(freezingY) - 16)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .allowsHitTesting(false)
  }

  private func insetLabel(_ text: String, unitY: Double) -> some View {
    Text(verbatim: text)
      .font(.caption2)
      .monospacedDigit()
      .foregroundStyle(.white.opacity(0.75))
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(.ultraThinMaterial, in: .capsule)
      .offset(x: 4, y: canvasY(unitY) - 9)
  }

  @ChartContentBuilder
  private var iconRow: some ChartContent {
    ForEach(context.model.weatherIcons(for: context.zoom)) { glyph in
      PointMark(
        x: .value("Hour", glyph.date),
        y: .value("Wetter", MeteogramModel.CanvasZone.iconRowY)
      )
      .symbol {
        Image(glyph.iconName)
          .resizable()
          .scaledToFit()
          .frame(width: 20, height: 20)
          .opacity(glyph.isPast ? 0.45 : 1)
      }
    }
  }

  @ChartContentBuilder
  private var temperatureLayers: some ChartContent {
    // Freezing level (0 °C / 32 °F) — snow-vs-rain context for the bars below.
    if let freezingY = context.model.freezingUnitY {
      RuleMark(y: .value("Frostgrenze", freezingY))
        .foregroundStyle(.cyan.opacity(0.22))
        .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
    }

    LinePlot(
      context.model.tempPast,
      x: .value("Hour", \.date),
      y: .value("Temperatur", \.value),
      series: .value("Series", "temp-past")
    )
    .interpolationMethod(.catmullRom)
    .foregroundStyle(.orange.opacity(0.42))
    .lineStyle(.init(lineWidth: 3, dash: [7, 5]))

    LinePlot(
      context.model.tempFuture,
      x: .value("Hour", \.date),
      y: .value("Temperatur", \.value),
      series: .value("Series", "temp-future")
    )
    .interpolationMethod(.catmullRom)
    .foregroundStyle(.orange)
    .lineStyle(.init(lineWidth: 3))

    // Pressure shares the area on its own normalized scale (thin, purple).
    LinePlot(
      context.model.pressurePast,
      x: .value("Hour", \.date),
      y: .value("Luftdruck", \.value),
      series: .value("Series", "pressure-past")
    )
    .interpolationMethod(.catmullRom)
    .foregroundStyle(.purple.opacity(0.35))
    .lineStyle(.init(lineWidth: 1.5, dash: [7, 5]))

    LinePlot(
      context.model.pressureFuture,
      x: .value("Hour", \.date),
      y: .value("Luftdruck", \.value),
      series: .value("Series", "pressure-future")
    )
    .interpolationMethod(.catmullRom)
    .foregroundStyle(.purple.opacity(0.75))
    .lineStyle(.init(lineWidth: 1.5))

    ForEach(context.model.extremaLabels) { label in
      PointMark(
        x: .value("Hour", label.date),
        y: .value("Temperatur", label.y)
      )
      .opacity(0)
      .annotation(
        position: label.isMax ? .top : .bottom, spacing: 4,
        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
      ) {
        Text(label.text)
          .font(.footnote.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(label.isMax ? .white : .white.opacity(0.55))
          .shadow(color: .black.opacity(0.35), radius: 2)
      }
    }
  }

  @ChartContentBuilder
  private var precipitationBars: some ChartContent {
    ForEach(context.model.precipBars) { bar in
      if bar.snowTop > 0 {
        BarMark(
          x: .value("Hour", bar.date),
          yStart: .value("Base", 0),
          yEnd: .value("Schnee", bar.snowTop)
        )
        .foregroundStyle(
          .linearGradient(
            colors: bar.isPast
              ? [.cyan.opacity(0.36), .cyan.opacity(0.2)]
              : [.cyan, .cyan.opacity(0.6)],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .cornerRadius(1.5)
      }
      if bar.rainTop > bar.snowTop {
        BarMark(
          x: .value("Hour", bar.date),
          yStart: .value("Schnee", bar.snowTop),
          yEnd: .value("Regen", bar.rainTop)
        )
        .foregroundStyle(
          .linearGradient(
            colors: bar.isPast
              ? [.blue.opacity(0.36), .blue.opacity(0.2)]
              : [.blue, .blue.opacity(0.7)],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .cornerRadius(1.5)
      }
    }
  }

  @ChartContentBuilder
  private var structureOverlays: some ChartContent {
    meteogramDayRules(context)
    meteogramNowRule(context)

    if let tempY = context.model.temperatureUnitY(at: context.model.currentIndex) {
      meteogramDotPair(
        date: context.model.dates[context.model.currentIndex], value: tempY,
        series: "Temperatur")
    }

    // Selection: house-style lollipop tooltip anchored to the cursor.
    if let date = context.selectedDate, let index = context.selectedIndex {
      RuleMark(x: .value("Selected", date))
        .foregroundStyle(.white.opacity(0.35))
        .lineStyle(.init(lineWidth: 1.5))
        .annotation(
          position: .topTrailing, spacing: 0,
          overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
        ) {
          MeteogramSelectionTooltip(model: context.model, index: index)
        }
    }
    if let index = context.selectedIndex,
      let tempY = context.model.temperatureUnitY(at: index)
    {
      meteogramDotPair(date: context.model.dates[index], value: tempY, series: "Temperatur")
    }
  }
}

// MARK: - Wind strip

private struct MeteogramWindStrip: View {
  let context: MeteogramPanelContext
  @Binding var rawSelection: Date?

  var body: some View {
    let model = context.model
    Chart {
      if !model.gustBand.isEmpty {
        AreaPlot(
          model.gustBand,
          x: .value("Hour", \.date),
          yStart: .value("Wind", \.yStart),
          yEnd: .value("Böen", \.yEnd),
          series: .value("Series", "gust-band")
        )
        .interpolationMethod(.monotone)
        .foregroundStyle(.teal.opacity(0.14))

        LinePlot(
          model.gustLine,
          x: .value("Hour", \.date),
          y: .value("Böen", \.value),
          series: .value("Series", "gusts")
        )
        .interpolationMethod(.monotone)
        .foregroundStyle(.teal.opacity(0.5))
        .lineStyle(.init(lineWidth: 1.5, lineCap: .round, dash: [2, 4]))
      }

      LinePlot(
        model.windPast,
        x: .value("Hour", \.date),
        y: .value("Wind", \.value),
        series: .value("Series", "wind-past")
      )
      .interpolationMethod(.catmullRom)
      .foregroundStyle(.teal.opacity(0.42))
      .lineStyle(.init(lineWidth: 2.5, dash: [7, 5]))

      LinePlot(
        model.windFuture,
        x: .value("Hour", \.date),
        y: .value("Wind", \.value),
        series: .value("Series", "wind-future")
      )
      .interpolationMethod(.catmullRom)
      .foregroundStyle(.teal)
      .lineStyle(.init(lineWidth: 2.5))

      ForEach(model.arrows(for: context.zoom)) { glyph in
        PointMark(
          x: .value("Hour", glyph.date),
          y: .value("Wind", model.arrowRowY)
        )
        .symbol {
          Image(systemName: glyph.iconName)
            .resizable()
            .frame(width: 10, height: 10)
            .rotationEffect(.degrees(glyph.degrees))
            .foregroundStyle(glyph.isPast ? .teal.opacity(0.42) : .teal)
            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
        }
      }

      meteogramDayRules(context)
      meteogramNowRule(context)

      if let value = model.windValue(at: model.currentIndex) {
        meteogramDotPair(date: model.dates[model.currentIndex], value: value, series: "Wind")
      }

      if let date = context.selectedDate {
        meteogramSelectionRule(at: date)
      }
      if let index = context.selectedIndex, let value = model.windValue(at: index) {
        meteogramDotPair(date: model.dates[index], value: value, series: "Wind")
      }
    }
    .chartYScale(domain: model.windDomain)
    .meteogramLabeledAxis(context)
    .meteogramPanelBase(context, rawSelection: $rawSelection)
    .frame(height: 96)
  }
}
