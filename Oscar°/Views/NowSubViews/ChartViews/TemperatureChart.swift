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
    VStack(alignment: .leading) {
      Chart {
        // Temperature line
        ForEach(temperatureData) { dataPoint in
          LineMark(
            x: .value("Hour", dataPoint.time),
            y: .value("Temperature (\(unit))", dataPoint.temperature),
            series: .value("Series", "Temperature")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.orange)
          .lineStyle(.init(lineWidth: 3))
        }

        // Apparent temperature line  
        ForEach(temperatureData) { dataPoint in
          LineMark(
            x: .value("Hour", dataPoint.time),
            y: .value("Gefühlte Temperature (\(unit))", dataPoint.apparentTemperature),
            series: .value("Series", "Apparent Temperature")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.red)
          .lineStyle(.init(lineWidth: 3))
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
              if let selectedData = getSelectedTemperatureData(for: selectedDate) {
                VStack(alignment: .center, spacing: 2) {
                  Text(formatTimeToHHMM(date: selectedDate))
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
                .cornerRadius(8)
                .shadow(radius: 4)
              }
            }
        }

        ForEach(dayChangeIndices(time: temperatureData.map { $0.time }), id: \.self) { index in
          RuleMark(x: .value("Hour", temperatureData[index].time))
            .foregroundStyle(.gray.opacity(0.6))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
            .annotation(
              position: .topTrailing, spacing: 8,
              overflowResolution: .init(
                x: .fit(to: .chart),
                y: .fit(to: .chart)
              )
            ) {
              Text(dayAbbreviation(from: temperatureData[index].time))
                .font(.caption.weight(.medium))
                .foregroundColor(.primary.opacity(0.7))
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
  
  /// Gets the nearest temperature data for a selected date
  func getSelectedTemperatureData(for selectedDate: Date) -> TemperatureData? {
    return temperatureData.min(by: { abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate)) })
  }
  
  /// Formats time to HH:MM format
  func formatTimeToHHMM(date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }
  
}
