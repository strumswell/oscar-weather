import Charts
import SwiftUI

// MARK: - Hero canvas

private let meteogramCanvasHeight: CGFloat = 300

private func canvasY(_ unitY: Double) -> CGFloat {
  meteogramCanvasHeight * (1 - CGFloat(unitY))
}

struct MeteogramCanvas: View {
  let context: MeteogramPanelContext
  let selection: Binding<Date?>

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
    .meteogramPanelBase(context, selection: selection)
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
