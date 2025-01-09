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
    VStack(alignment: .leading) {
      Chart {
        if #available(iOS 18, *) {
          LinePlot(
            temperatureData,
            x: .value("Hour", \.time),
            y: .value("Temperature (\(unit))", \.temperature),
            series: .value("Series", "Temperature")
          )
          .foregroundStyle(.orange)
          .interpolationMethod(.catmullRom)

          LinePlot(
            temperatureData,
            x: .value("Hour", \.time),
            y: .value("Gefühlte Temperature (\(unit))", \.apparentTemperature),
            series: .value("Series", "Apparent Temperature")
          )
          .foregroundStyle(.red)
          .interpolationMethod(.catmullRom)
        } else {
          ForEach(temperatureData) { dataPoint in
            LineMark(
              x: .value("Hour", dataPoint.time),
              y: .value("Temperature (\(unit))", dataPoint.temperature),
              series: .value("Series", "Temperature")
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.orange)
          }

          ForEach(temperatureData) { dataPoint in
            LineMark(
              x: .value("Hour", dataPoint.time),
              y: .value("Gefühlte Temperature (\(unit))", dataPoint.apparentTemperature),
              series: .value("Series", "Apparent Temperature")
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.red)
          }
        }

        ForEach(dayChangeIndices(time: temperatureData.map { $0.time }), id: \.self) { index in
          RuleMark(x: .value("Hour", temperatureData[index].time))
            .foregroundStyle(.gray)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
            .annotation(
              position: .topTrailing, spacing: 5,
              overflowResolution: .init(
                x: .fit(to: .chart),
                y: .fit(to: .chart)
              )
            ) {
              Text(dayAbbreviation(from: temperatureData[index].time))
                .font(.caption)
                .foregroundColor(.gray)
            }
        }
      }
      .chartForegroundStyleScale([
        "Temperature (\(unit))": .orange,
        "Gefühlte Temperature (\(unit))": .red,
      ])
      .chartXAxis {
        AxisMarks(values: .stride(by: .hour, count: 6)) { value in
          AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
          AxisGridLine()
          AxisTick()
        }
      }
      .chartXScale(domain: maxTimeRange)
      .chartScrollableAxes(.horizontal)
      .chartXVisibleDomain(length: 129600)
      .frame(height: 175)
    }
  }

  /// Identifies the indices where the day changes in the time array.
  func dayChangeIndices(time: [Date]) -> [Int] {
    var indices: [Int] = []
    for i in 1..<time.count {
      let currentDate = time[i]
      let previousDate = time[i - 1]
      let calendar = Calendar.current
      if !calendar.isDate(currentDate, inSameDayAs: previousDate) {
        indices.append(i)
      }
    }
    return indices
  }

  /// Returns a short abbreviation for the day of the week from a Date.
  func dayAbbreviation(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateFormat = "E"  // Short day abbreviation, e.g., Mon, Tue
    return formatter.string(from: date)
  }
}
