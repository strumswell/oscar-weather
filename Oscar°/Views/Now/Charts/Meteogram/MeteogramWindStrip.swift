import Charts
import SwiftUI

// MARK: - Wind strip

struct MeteogramWindStrip: View {
  let context: MeteogramPanelContext
  let selection: Binding<Date?>

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
    .meteogramPanelBase(context, selection: selection)
    .frame(height: 96)
  }
}
