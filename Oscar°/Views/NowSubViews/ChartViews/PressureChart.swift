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

  var body: some View {
    VStack(alignment: .leading) {
      let minPressure = pressure.min() ?? 0
      let maxPressure = pressure.max() ?? 100
      let tickValues = calculateTicks(from: minPressure, to: maxPressure, count: 4)

      Chart {
        ForEach(Array(zip(time, pressure).enumerated()), id: \.offset) { index, pair in
          let (timeValue, pressureValue) = pair
          LineMark(
            x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
            y: .value("Pressure", pressureValue),
            series: .value("Series", "Pressure")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.purple)
        }

        ForEach(dayChangeIndices(time: time), id: \.self) { index in
          RuleMark(x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))))
            .foregroundStyle(.gray)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
            .annotation(
              position: .topTrailing, spacing: 5,
              overflowResolution: .init(
                x: .fit(to: .chart),
                y: .fit(to: .chart)
              )
            ) {
              Text(dayAbbreviation(from: Date(timeIntervalSince1970: TimeInterval(time[index]))))
                .font(.caption)
                .foregroundColor(.gray)
            }
        }
      }
      .chartForegroundStyleScale([String(localized: "Luftdruck") + " (\(unit))": .purple])
      .chartXAxis {
        AxisMarks(values: .stride(by: .hour, count: 6)) { value in
          AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
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
      .chartYScale(domain: minPressure...maxPressure)
      .chartXScale(domain: maxTimeRange)
      .chartScrollableAxes(.horizontal)
      .chartXVisibleDomain(length: 129600)
      .frame(height: 175)
    }
  }
}
