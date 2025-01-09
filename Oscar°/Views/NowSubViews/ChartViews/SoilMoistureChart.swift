//
//  SoilMoistureChart.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.08.24.
//

import Charts
import SwiftUI

struct SoilMoistureChart: View {
  var soilMoisture0_1cm: [Double?]
  var soilMoisture1_3cm: [Double?]
  var soilMoisture3_9cm: [Double?]
  var soilMoisture9_27cm: [Double?]
  var soilMoisture27_81cm: [Double?]
  var time: [Double]
  var unit: String
  var maxTimeRange: ClosedRange<Date>

  var body: some View {
    VStack(alignment: .leading) {
      Chart {
        ForEach(Array(zip(time, soilMoisture0_1cm).enumerated()), id: \.offset) { index, pair in
          if let moistureValue = pair.1 {
            LineMark(
              x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(pair.0))),
              y: .value("0-1cm", moistureValue),
              series: .value("Series", "Bodenwassergehalt 0-1cm (\(unit))")
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.brown)
          }
        }

        ForEach(Array(zip(time, soilMoisture1_3cm).enumerated()), id: \.offset) { index, pair in
          if let moistureValue = pair.1 {
            LineMark(
              x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(pair.0))),
              y: .value("1-3cm", moistureValue),
              series: .value("Series", "Bodenwassergehalt 1-3cm (\(unit))")
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.brown.opacity(0.6))
          }
        }

        ForEach(Array(zip(time, soilMoisture3_9cm).enumerated()), id: \.offset) { index, pair in
          if let moistureValue = pair.1 {
            LineMark(
              x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(pair.0))),
              y: .value("3-9cm", moistureValue),
              series: .value("Series", "Bodenwassergehalt 3-9cm (\(unit))")
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.brown.opacity(0.4))
          }
        }

        ForEach(Array(zip(time, soilMoisture9_27cm).enumerated()), id: \.offset) { index, pair in
          if let moistureValue = pair.1 {
            LineMark(
              x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(pair.0))),
              y: .value("9-27cm", moistureValue),
              series: .value("Series", "Bodenwassergehalt 9-27cm (\(unit))")
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.brown.opacity(0.2))
          }
        }

        ForEach(Array(zip(time, soilMoisture27_81cm).enumerated()), id: \.offset) { index, pair in
          if let moistureValue = pair.1 {
            LineMark(
              x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(pair.0))),
              y: .value("27-81cm", moistureValue),
              series: .value("Series", "Bodenwassergehalt 27-81cm (\(unit))")
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.brown.opacity(0.1))
          }
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
      .chartForegroundStyleScale([
        "0-1cm (\(unit))": .brown,
        "1-3cm (\(unit))": .brown.opacity(0.6),
        "3-9cm (\(unit))": .brown.opacity(0.4),
        "9-27cm (\(unit))": .brown.opacity(0.2),
        "27-81cm (\(unit))": .brown.opacity(0.1),
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
      .frame(height: 200)
    }
  }
}
