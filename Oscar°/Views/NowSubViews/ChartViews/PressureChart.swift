//
//  PressureChart.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.08.24.
//

import Charts
import SwiftUI

struct PressureChart: View {
  var pressure: [Double]
  var time: [Double]
  var unit: String
  var maxTimeRange: ClosedRange<Date>
  var referenceDate: Date
  
  @State private var selectedDate: Date?

  private var minPressure: Double { pressure.min() ?? 0 }
  private var maxPressure: Double { pressure.max() ?? 100 }
  private var pressureSpan: Double { max(maxPressure - minPressure, 1) }
  /// The value the area fill bottoms out at. Sitting a little below the lowest
  /// reading gives the area some body at the dips without reaching the axis.
  private var areaBaseline: Double { minPressure - max(pressureSpan * 0.15, 2) }

  var pressureData: [(time: Date, pressure: Double, baseline: Double)] {
    let count = min(time.count, pressure.count)
    let baseline = areaBaseline
    return (0..<count).map { index in
      (time: Date(timeIntervalSince1970: time[index]), pressure: pressure[index], baseline: baseline)
    }
  }

  private var currentDataPoint: (time: Date, pressure: Double, baseline: Double)? {
    pressureData.first(where: { $0.time >= referenceDate }) ?? pressureData.last
  }

  var body: some View {
    VStack(alignment: .leading) {
      // Branch on availability at the View level rather than inside the
      // Chart's ChartContentBuilder: an `if #available` there produces a
      // `_ConditionalContent` whose ChartContent conformance is iOS 27+ only.
      // Routing each plot variant through the generic `chart(plot:)` helper
      // keeps the plot's ChartContent type concrete and avoids that.
      if #available(iOS 18, *) {
        chart {
          // Area plot with gradient. Filling from a baseline above the scale's
          // lower bound (rather than `y:`, which fills to the bottom of the
          // scale) keeps the area off the x-axis.
          AreaPlot(
            pressureData.filter { $0.time >= referenceDate },
            x: .value("Hour", \.time),
            yStart: .value("Baseline", \.baseline),
            yEnd: .value("Luftdruck (\(unit))", \.pressure)
          )
          .foregroundStyle(
            .linearGradient(
              colors: [.purple.opacity(0.3), .purple.opacity(0.05)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .interpolationMethod(.catmullRom)

          LinePlot(
            pressureData.filter { $0.time <= referenceDate },
            x: .value("Hour", \.time),
            y: .value("Luftdruck (\(unit))", \.pressure),
            series: .value("Series", "Pressure-past")
          )
          .foregroundStyle(.purple.opacity(0.42))
          .interpolationMethod(.catmullRom)
          .lineStyle(.init(lineWidth: 2.5, dash: [7, 5]))

          LinePlot(
            pressureData.filter { $0.time >= referenceDate },
            x: .value("Hour", \.time),
            y: .value("Luftdruck (\(unit))", \.pressure),
            series: .value("Series", "Pressure-future")
          )
          .foregroundStyle(.purple)
          .interpolationMethod(.catmullRom)
          .lineStyle(.init(lineWidth: 2.5))
        }
      } else {
        chart {
          // iOS 17 fallback
          ForEach(Array(zip(time, pressure).enumerated()), id: \.offset) { index, pair in
            let (timeValue, pressureValue) = pair
            AreaMark(
              x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
              yStart: .value("Baseline", areaBaseline),
              yEnd: .value("Luftdruck (\(unit))", pressureValue)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(timeValue < referenceDate.timeIntervalSince1970 ? .purple.opacity(0.08) : .purple.opacity(0.2))
          }

          ForEach(Array(zip(time, pressure).enumerated()), id: \.offset) { index, pair in
            let (timeValue, pressureValue) = pair
            LineMark(
              x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
              y: .value("Luftdruck (\(unit))", pressureValue),
              series: .value("Series", timeValue < referenceDate.timeIntervalSince1970 ? "Pressure-past" : "Pressure-future")
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(timeValue < referenceDate.timeIntervalSince1970 ? .purple.opacity(0.42) : .purple)
            .lineStyle(timeValue < referenceDate.timeIntervalSince1970 ? .init(lineWidth: 2.5, dash: [7, 5]) : .init(lineWidth: 2.5))
          }
        }
      }
    }
  }

  /// Builds the pressure chart around the supplied plot content, applying the
  /// shared marks, axes, and scales. Generic over the plot's `ChartContent`
  /// type so each availability branch passes a concrete type.
  @ViewBuilder
  private func chart<Plot: ChartContent>(@ChartContentBuilder plot: () -> Plot) -> some View {
    let tickValues = HourlyChartUtilities.ticks(from: minPressure, to: maxPressure, count: 4)
    // Extend the scale below the area's baseline so the fill floats above the
    // bottom axis with a visible gap, instead of bleeding onto the x-axis
    // labels (ticks stay on the data range).
    let domainLowerBound = areaBaseline - max(pressureSpan * 0.25, 4)
    let domainUpperBound = maxPressure + max(pressureSpan * 0.15, 2)

    Chart {
      plot()

      currentPointMarks

      // Interactive selection indicator
      if let selectedDate {
        RuleMark(x: .value("Selected", selectedDate))
          .foregroundStyle(.gray.opacity(0.3))
          .lineStyle(.init(lineWidth: 2))
          .annotation(
            position: .topTrailing, spacing: 0,
            overflowResolution: .init(
              x: .fit(to: .chart),
              y: .fit(to: .chart)
            )
          ) {
            if let selectedData = getSelectedPressureData(for: selectedDate) {
              VStack(alignment: .center, spacing: 2) {
                Text(HourlyChartUtilities.timeString(from: selectedDate))
                  .font(.caption)
                  .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                  HStack(spacing: 4) {
                    Circle().fill(.purple).frame(width: 6, height: 6)
                    Text("\(selectedData.pressure, specifier: "%.0f") \(unit)")
                      .font(.caption2)
                      .foregroundStyle(.white)
                  }
                }
              }
              .padding(8)
              .background(.ultraThinMaterial.opacity(0.9))
              .clipShape(.rect(cornerRadius: 8))
              .shadow(radius: 4)
            }
          }
      }

      ForEach(dayChangeIndices(time: time), id: \.self) { index in
        RuleMark(x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))))
          .foregroundStyle(.gray.opacity(0.6))
          .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
          .annotation(
            position: .topTrailing, spacing: 8,
            overflowResolution: .init(
              x: .fit(to: .chart),
              y: .fit(to: .chart)
            )
          ) {
            Text(HourlyChartUtilities.dayAbbreviation(from: Date(timeIntervalSince1970: TimeInterval(time[index]))))
              .font(.caption.weight(.medium))
              .foregroundStyle(.primary.opacity(0.7))
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.ultraThinMaterial, in: .capsule)
          }
      }
    }
    .chartForegroundStyleScale([String(localized: "Luftdruck") + " (\(unit))": .purple])
    .chartXAxis {
      AxisMarks(values: .stride(by: .hour, count: 6)) { value in
        AxisValueLabel {
          if let date = value.as(Date.self) {
            Text(HourlyChartUtilities.hourString(from: date))
          }
        }
        AxisGridLine()
        AxisTick()
      }
    }
    .chartYAxis {
      AxisMarks(values: tickValues) { value in
        AxisValueLabel {
          if let pressureValue = value.as(Double.self) {
            Text("\(pressureValue, specifier: "%.0f")")
          }
        }
        AxisGridLine()
        AxisTick()
      }
    }
    .chartYScale(domain: domainLowerBound...domainUpperBound)
    .chartXScale(domain: maxTimeRange)
    .chartScrollableAxes(.horizontal)
    .chartXVisibleDomain(length: 129600)
    .chartXSelection(value: $selectedDate)
    .frame(height: 175)
  }
  
  /// Gets the nearest pressure data for a selected date
  private func getSelectedPressureData(for selectedDate: Date) -> (time: Date, pressure: Double, baseline: Double)? {
    return pressureData.min(by: { abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate)) })
  }

  @ChartContentBuilder
  private var currentPointMarks: some ChartContent {
    if let currentDataPoint {
      PointMark(
        x: .value("Current Hour", currentDataPoint.time),
        y: .value("Luftdruck", currentDataPoint.pressure)
      )
      .symbol(.circle)
      .symbolSize(90)
      .foregroundStyle(.black)

      PointMark(
        x: .value("Current Hour", currentDataPoint.time),
        y: .value("Luftdruck", currentDataPoint.pressure)
      )
      .symbol(.circle)
      .symbolSize(42)
      .foregroundStyle(.white)
    }
  }
}
