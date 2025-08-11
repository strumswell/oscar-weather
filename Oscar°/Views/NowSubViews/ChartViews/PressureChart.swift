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
  
  @State private var selectedDate: Date?

  var pressureData: [(time: Date, pressure: Double)] {
    let count = min(time.count, pressure.count)
    return (0..<count).map { index in
      (time: Date(timeIntervalSince1970: time[index]), pressure: pressure[index])
    }
  }

  var body: some View {
    VStack(alignment: .leading) {
      let minPressure = pressure.min() ?? 0
      let maxPressure = pressure.max() ?? 100
      let tickValues = calculateTicks(from: minPressure, to: maxPressure, count: 4)

      Chart {
        if #available(iOS 18, *) {
          // Area plot with gradient
          AreaPlot(
            pressureData,
            x: .value("Hour", \.time),
            y: .value("Luftdruck (\(unit))", \.pressure)
          )
          .foregroundStyle(
            .linearGradient(
              colors: [.purple.opacity(0.3), .purple.opacity(0.05)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .interpolationMethod(.catmullRom)
          
          // Line plot on top
          LinePlot(
            pressureData,
            x: .value("Hour", \.time),
            y: .value("Luftdruck (\(unit))", \.pressure),
            series: .value("Series", "Pressure")
          )
          .foregroundStyle(.purple)
          .interpolationMethod(.catmullRom)
          .lineStyle(.init(lineWidth: 2.5))
        } else {
          // iOS 17 fallback
          ForEach(Array(zip(time, pressure).enumerated()), id: \.offset) { index, pair in
            let (timeValue, pressureValue) = pair
            AreaMark(
              x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
              y: .value("Luftdruck (\(unit))", pressureValue)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.purple.opacity(0.2))
          }
          
          ForEach(Array(zip(time, pressure).enumerated()), id: \.offset) { index, pair in
            let (timeValue, pressureValue) = pair
            LineMark(
              x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
              y: .value("Luftdruck (\(unit))", pressureValue),
              series: .value("Series", "Pressure")
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.purple)
            .lineStyle(.init(lineWidth: 2.5))
          }
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
              if let selectedData = getSelectedPressureData(for: selectedDate) {
                VStack(alignment: .center, spacing: 2) {
                  Text(formatTimeToHHMM(date: selectedDate))
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
      .chartXSelection(value: $selectedDate)
      .frame(height: 175)
    }
  }
  
  /// Gets the nearest pressure data for a selected date
  private func getSelectedPressureData(for selectedDate: Date) -> (time: Date, pressure: Double)? {
    return pressureData.min(by: { abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate)) })
  }
  
  /// Formats time to HH:MM format
  private func formatTimeToHHMM(date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }
}
