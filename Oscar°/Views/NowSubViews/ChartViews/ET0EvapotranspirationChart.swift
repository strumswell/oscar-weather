//
//  ET0EvapotranspirationChart.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.08.24.
//

import Charts
import SwiftUI

struct ET0EvapotranspirationChart: View {
  var et0: [Double]
  var time: [Double]
  var unit: String
  var maxTimeRange: ClosedRange<Date>
  
  @State private var selectedDate: Date?

  var et0Data: [(time: Date, et0: Double)] {
    let count = min(time.count, et0.count)
    return (0..<count).map { index in
      (time: Date(timeIntervalSince1970: time[index]), et0: et0[index])
    }
  }

  var body: some View {
    VStack(alignment: .leading) {
      Chart {
        ForEach(Array(zip(time, et0).enumerated()), id: \.offset) { index, pair in
          let (timeValue, et0Value) = pair
          LineMark(
            x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
            y: .value("ET0", et0Value),
            series: .value("Series", "ET0 FAO (\(unit))")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.blue)
        }
        
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
              if let selectedData = getSelectedET0Data(for: selectedDate) {
                VStack(alignment: .center, spacing: 2) {
                  Text(formatTimeToHHMM(date: selectedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  
                  VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                      Circle().fill(.blue).frame(width: 6, height: 6)
                      Text("\(selectedData.et0, specifier: "%.2f")\(unit)")
                        .font(.caption2)
                        .foregroundStyle(.white)
                    }
                  }
                }
                .padding(8)
                .background(.ultraThinMaterial.opacity(0.9))
                .cornerRadius(8)
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
              Text(dayAbbreviation(from: Date(timeIntervalSince1970: TimeInterval(time[index]))))
                .font(.caption.weight(.medium))
                .foregroundColor(.primary.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: .capsule)
            }
        }
      }
      .chartForegroundStyleScale([
        String(localized: "Referenz-Evapotranspiration") + " (\(unit))": .blue
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
      .chartXSelection(value: $selectedDate)
      .frame(height: 175)
    }
  }
  
  /// Gets the nearest ET0 data for a selected date
  private func getSelectedET0Data(for selectedDate: Date) -> (time: Date, et0: Double)? {
    return et0Data.min(by: { abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate)) })
  }
  
  /// Formats time to HH:MM format
  private func formatTimeToHHMM(date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }
}
