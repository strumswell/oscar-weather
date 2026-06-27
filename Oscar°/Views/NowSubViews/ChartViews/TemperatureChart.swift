//
//  TemperatureChart.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.08.24.
//

import Charts
import SwiftUI

struct TemperatureData: Identifiable {
  let id: Int
  let time: Date
  let temperature: Double
  let apparentTemperature: Double
}

struct TemperatureChart: View {
  var temperature: [Double]
  var apparentTemperature: [Double]
  var time: [Double]
  var unit: String
  var maxTimeRange: ClosedRange<Date>
  var referenceDate: Date

  @State private var selectedDate: Date?

  var temperatureData: [TemperatureData] {
    // Ensure all arrays have the same length
    let count = min(time.count, min(temperature.count, apparentTemperature.count))
    return (0..<count).map { index in
      TemperatureData(
        id: index,
        time: Date(timeIntervalSince1970: time[index]),
        temperature: temperature[index],
        apparentTemperature: apparentTemperature[index]
      )
    }
  }

  var body: some View {
    // Build the series once per body evaluation. `.chartXSelection` mutates `selectedDate`
    // on every drag sample, so body re-runs continuously while scrubbing — recomputing the
    // mapped array and its filters here (instead of in each ForEach/helper) keeps that cheap.
    let data = temperatureData
    let past = data.filter { $0.time <= referenceDate }
    let future = data.filter { $0.time >= referenceDate }
    let dayChanges = HourlyChartUtilities.dayChangeIndices(time: data.map { $0.time })
    let current = data.first(where: { $0.time >= referenceDate }) ?? data.last

    return VStack(alignment: .leading) {
      Chart {
        ForEach(past) { dataPoint in
          LineMark(
            x: .value("Hour", dataPoint.time),
            y: .value("Temperature (\(unit))", dataPoint.temperature),
            series: .value("Series", "Temperature-past")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.orange.opacity(0.42))
          .lineStyle(.init(lineWidth: 3, dash: [7, 5]))
        }

        ForEach(future) { dataPoint in
          LineMark(
            x: .value("Hour", dataPoint.time),
            y: .value("Temperature (\(unit))", dataPoint.temperature),
            series: .value("Series", "Temperature-future")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.orange)
          .lineStyle(.init(lineWidth: 3))
        }

        ForEach(past) { dataPoint in
          LineMark(
            x: .value("Hour", dataPoint.time),
            y: .value("Gefühlte Temperature (\(unit))", dataPoint.apparentTemperature),
            series: .value("Series", "Apparent Temperature-past")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.red.opacity(0.42))
          .lineStyle(.init(lineWidth: 3, dash: [7, 5]))
        }

        ForEach(future) { dataPoint in
          LineMark(
            x: .value("Hour", dataPoint.time),
            y: .value("Gefühlte Temperature (\(unit))", dataPoint.apparentTemperature),
            series: .value("Series", "Apparent Temperature-future")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.red)
          .lineStyle(.init(lineWidth: 3))
        }

        currentPointMarks(for: current)

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
              if let selectedData = getSelectedTemperatureData(for: selectedDate, in: data) {
                VStack(alignment: .center, spacing: 2) {
                  Text(HourlyChartUtilities.timeString(from: selectedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                  VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                      Circle().fill(.orange).frame(width: 6, height: 6)
                      Text("\(selectedData.temperature, specifier: "%.1f")\(unit)")
                        .font(.caption2)
                        .foregroundStyle(.white)
                    }

                    HStack(spacing: 4) {
                      Circle().fill(.red).frame(width: 6, height: 6)
                      Text("\(selectedData.apparentTemperature, specifier: "%.1f")\(unit)")
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

        ForEach(dayChanges, id: \.self) { index in
          RuleMark(x: .value("Hour", data[index].time))
            .foregroundStyle(.gray.opacity(0.6))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
            .annotation(
              position: .topTrailing, spacing: 8,
              overflowResolution: .init(
                x: .fit(to: .chart),
                y: .fit(to: .chart)
              )
            ) {
              Text(HourlyChartUtilities.dayAbbreviation(from: data[index].time))
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: .capsule)
            }
        }
      }
      .chartForegroundStyleScale([
        "Temperature (\(unit))": .orange,
        "Gefühlte Temperature (\(unit))": .red,
      ])
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
      .chartXScale(domain: maxTimeRange)
      .chartScrollableAxes(.horizontal)
      .chartXVisibleDomain(length: 129600)
      .chartXSelection(value: $selectedDate)
      .frame(height: 175)
    }
  }

  /// Gets the nearest temperature data for a selected date
  func getSelectedTemperatureData(for selectedDate: Date, in data: [TemperatureData]) -> TemperatureData? {
    return data.min(by: { abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate)) })
  }

  @ChartContentBuilder
  private func currentPointMarks(for current: TemperatureData?) -> some ChartContent {
    if let current {
      currentPointMark(time: current.time, series: "Temperature", value: current.temperature)
      currentPointMark(time: current.time, series: "Apparent Temperature", value: current.apparentTemperature)
    }
  }

  @ChartContentBuilder
  private func currentPointMark(time: Date, series: String, value: Double) -> some ChartContent {
    PointMark(
      x: .value("Current Hour", time),
      y: .value(series, value)
    )
    .symbol(.circle)
    .symbolSize(90)
    .foregroundStyle(.black)

    PointMark(
      x: .value("Current Hour", time),
      y: .value(series, value)
    )
    .symbol(.circle)
    .symbolSize(42)
    .foregroundStyle(.white)
  }
}
