//
//  PrecipitationChart.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.08.24.
//

import Charts
import SwiftUI

struct PrecipitationChart: View {
  var precipitation: [Double]
  var snowfall: [Double]
  var time: [Double]
  var unit: String
  var maxTimeRange: ClosedRange<Date>

  var body: some View {
    if precipitation.max() == 0 && snowfall.max() == 0 {
      ContentUnavailableView(
        "Kein Niederschlag", image: "icloud.slash",
        description: Text("Für die nächsten Tage wird kein Niederschlag vorhergesagt.")
      )
      .frame(height: 175)
    } else {
      VStack(alignment: .leading) {
        Chart {
          ForEach(Array(zip(time, precipitation).enumerated()), id: \.offset) { index, pair in
            let (timeValue, precip) = pair
            let snow = snowfall[index]
            let rainOnly = max(0, precip - snow)  // Subtract snowfall to get rain only

            // Snowfall bar (bottom)
            if snow > 0 {
              BarMark(
                x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
                y: .value("Schnee (\(unit))", snow)
              )
              .foregroundStyle(.cyan)
            }

            // Rain bar (top)
            if rainOnly > 0 {
              BarMark(
                x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
                y: .value("Regen (\(unit))", rainOnly)
              )
              .foregroundStyle(.blue)
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
          String(localized: "Regen") + " (\(unit))": .blue,
          String(localized: "Schnee") + " (\(unit))": .cyan,
        ])
        .chartXAxis {
          AxisMarks(values: .stride(by: .hour, count: 6)) { value in
            AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)))
            AxisGridLine()
            AxisTick()
          }
        }
        .chartYAxis {
          AxisMarks { value in
            AxisValueLabel {
              if let precipitation = value.as(Double.self) {
                Text("\(precipitation, specifier: "%.1f")")
              }
            }
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
  }
}
