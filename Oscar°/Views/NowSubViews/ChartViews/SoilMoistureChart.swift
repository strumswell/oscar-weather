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
  
  @State private var selectedDate: Date?

  var soilMoistureData: [(time: Date, moisture0_1: Double?, moisture1_3: Double?, moisture3_9: Double?, moisture9_27: Double?, moisture27_81: Double?)] {
    let count = min(time.count, min(soilMoisture0_1cm.count, min(soilMoisture1_3cm.count, min(soilMoisture3_9cm.count, min(soilMoisture9_27cm.count, soilMoisture27_81cm.count)))))
    return (0..<count).map { index in
      (time: Date(timeIntervalSince1970: time[index]),
       moisture0_1: soilMoisture0_1cm[index],
       moisture1_3: soilMoisture1_3cm[index],
       moisture3_9: soilMoisture3_9cm[index],
       moisture9_27: soilMoisture9_27cm[index],
       moisture27_81: soilMoisture27_81cm[index])
    }
  }

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
              if let selectedData = getSelectedSoilMoistureData(for: selectedDate) {
                VStack(alignment: .center, spacing: 2) {
                  Text(formatTimeToHHMM(date: selectedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  
                  VStack(alignment: .leading, spacing: 1) {
                    if let moisture0_1 = selectedData.moisture0_1 {
                      HStack(spacing: 4) {
                        Circle().fill(.brown.opacity(0.8)).frame(width: 6, height: 6)
                        Text("\(moisture0_1, specifier: "%.2f") (0-1cm)")
                          .font(.caption2)
                          .foregroundStyle(.white)
                      }
                    }
                    
                    if let moisture1_3 = selectedData.moisture1_3 {
                      HStack(spacing: 4) {
                        Circle().fill(.brown.opacity(0.7)).frame(width: 6, height: 6)
                        Text("\(moisture1_3, specifier: "%.2f") (1-3cm)")
                          .font(.caption2)
                          .foregroundStyle(.white)
                      }
                    }
                    
                    if let moisture3_9 = selectedData.moisture3_9 {
                      HStack(spacing: 4) {
                        Circle().fill(.brown.opacity(0.6)).frame(width: 6, height: 6)
                        Text("\(moisture3_9, specifier: "%.2f") (3-9cm)")
                          .font(.caption2)
                          .foregroundStyle(.white)
                      }
                    }
                    
                    if let moisture9_27 = selectedData.moisture9_27 {
                      HStack(spacing: 4) {
                        Circle().fill(.brown.opacity(0.5)).frame(width: 6, height: 6)
                        Text("\(moisture9_27, specifier: "%.2f") (9-27cm)")
                          .font(.caption2)
                          .foregroundStyle(.white)
                      }
                    }
                    
                    if let moisture27_81 = selectedData.moisture27_81 {
                      HStack(spacing: 4) {
                        Circle().fill(.brown.opacity(0.4)).frame(width: 6, height: 6)
                        Text("\(moisture27_81, specifier: "%.2f") (27-81cm)")
                          .font(.caption2)
                          .foregroundStyle(.white)
                      }
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
                .background(.regularMaterial, in: .capsule)
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
      .chartXSelection(value: $selectedDate)
      .frame(height: 200)
    }
  }
  
  /// Gets the nearest soil moisture data for a selected date
  private func getSelectedSoilMoistureData(for selectedDate: Date) -> (time: Date, moisture0_1: Double?, moisture1_3: Double?, moisture3_9: Double?, moisture9_27: Double?, moisture27_81: Double?)? {
    return soilMoistureData.min(by: { abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate)) })
  }
  
  /// Formats time to HH:MM format
  private func formatTimeToHHMM(date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }
  
  /// Identifies the indices where the day changes in the time array
  private func dayChangeIndices(time: [Double]) -> [Int] {
    var indices: [Int] = []
    for i in 1..<time.count {
      let currentDate = Date(timeIntervalSince1970: time[i])
      let previousDate = Date(timeIntervalSince1970: time[i - 1])
      let calendar = Calendar.current
      if !calendar.isDate(currentDate, inSameDayAs: previousDate) {
        indices.append(i)
      }
    }
    return indices
  }

  /// Returns a short abbreviation for the day of the week from a Date
  private func dayAbbreviation(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateFormat = "E"  // Short day abbreviation, e.g., Mon, Tue
    return formatter.string(from: date)
  }
}
