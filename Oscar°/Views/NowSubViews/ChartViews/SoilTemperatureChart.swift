//
//  SoilTemperatureChart.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.08.24.
//

import Charts
import SwiftUI

struct SoilTemperatureChart: View {
  var soilTemp0cm: [Double?]
  var soilTemp6cm: [Double?]
  var soilTemp18cm: [Double?]
  var soilTemp54cm: [Double?]
  var time: [Double]
  var unit: String
  var maxTimeRange: ClosedRange<Date>
  
  @State private var selectedDate: Date?

  var soilTempData: [(time: Date, temp0: Double?, temp6: Double?, temp18: Double?, temp54: Double?)] {
    let count = min(time.count, min(soilTemp0cm.count, min(soilTemp6cm.count, min(soilTemp18cm.count, soilTemp54cm.count))))
    return (0..<count).map { index in
      (time: Date(timeIntervalSince1970: time[index]),
       temp0: soilTemp0cm[index],
       temp6: soilTemp6cm[index],
       temp18: soilTemp18cm[index],
       temp54: soilTemp54cm[index])
    }
  }

  var body: some View {
    VStack(alignment: .leading) {
      Chart {
        if #available(iOS 18, *) {
          // 54cm depth (deepest, most stable)
          ForEach(soilTempData, id: \.time) { data in
            if let temp54 = data.temp54 {
              LinePlot(
                [(time: data.time, temp: temp54)],
                x: .value("Hour", \.time),
                y: .value("54cm (\(unit))", \.temp),
                series: .value("Series", "54cm")
              )
              .foregroundStyle(.brown.opacity(0.3))
              .interpolationMethod(.catmullRom)
              .lineStyle(.init(lineWidth: 2))
            }
          }
          
          // 18cm depth
          ForEach(soilTempData, id: \.time) { data in
            if let temp18 = data.temp18 {
              LinePlot(
                [(time: data.time, temp: temp18)],
                x: .value("Hour", \.time),
                y: .value("18cm (\(unit))", \.temp),
                series: .value("Series", "18cm")
              )
              .foregroundStyle(.brown.opacity(0.5))
              .interpolationMethod(.catmullRom)
              .lineStyle(.init(lineWidth: 2.5))
            }
          }
          
          // 6cm depth
          ForEach(soilTempData, id: \.time) { data in
            if let temp6 = data.temp6 {
              LinePlot(
                [(time: data.time, temp: temp6)],
                x: .value("Hour", \.time),
                y: .value("6cm (\(unit))", \.temp),
                series: .value("Series", "6cm")
              )
              .foregroundStyle(.brown.opacity(0.7))
              .interpolationMethod(.catmullRom)
              .lineStyle(.init(lineWidth: 3))
            }
          }
          
          // 0cm depth (surface)
          ForEach(soilTempData, id: \.time) { data in
            if let temp0 = data.temp0 {
              LinePlot(
                [(time: data.time, temp: temp0)],
                x: .value("Hour", \.time),
                y: .value("0cm (\(unit))", \.temp),
                series: .value("Series", "0cm")
              )
              .foregroundStyle(.brown)
              .interpolationMethod(.catmullRom)
              .lineStyle(.init(lineWidth: 3.5))
            }
          }
        } else {
          // iOS 17 fallback
          ForEach(Array(zip(time, soilTemp54cm).enumerated()), id: \.offset) { index, pair in
            if let tempValue = pair.1 {
              LineMark(
                x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(pair.0))),
                y: .value("54cm (\(unit))", tempValue),
                series: .value("Series", "54cm")
              )
              .interpolationMethod(.catmullRom)
              .foregroundStyle(.brown.opacity(0.3))
              .lineStyle(.init(lineWidth: 2))
            }
          }
          
          ForEach(Array(zip(time, soilTemp18cm).enumerated()), id: \.offset) { index, pair in
            if let tempValue = pair.1 {
              LineMark(
                x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(pair.0))),
                y: .value("18cm (\(unit))", tempValue),
                series: .value("Series", "18cm")
              )
              .interpolationMethod(.catmullRom)
              .foregroundStyle(.brown.opacity(0.5))
              .lineStyle(.init(lineWidth: 2.5))
            }
          }
          
          ForEach(Array(zip(time, soilTemp6cm).enumerated()), id: \.offset) { index, pair in
            if let tempValue = pair.1 {
              LineMark(
                x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(pair.0))),
                y: .value("6cm (\(unit))", tempValue),
                series: .value("Series", "6cm")
              )
              .interpolationMethod(.catmullRom)
              .foregroundStyle(.brown.opacity(0.7))
              .lineStyle(.init(lineWidth: 3))
            }
          }
          
          ForEach(Array(zip(time, soilTemp0cm).enumerated()), id: \.offset) { index, pair in
            if let tempValue = pair.1 {
              LineMark(
                x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(pair.0))),
                y: .value("0cm (\(unit))", tempValue),
                series: .value("Series", "0cm")
              )
              .interpolationMethod(.catmullRom)
              .foregroundStyle(.brown)
              .lineStyle(.init(lineWidth: 3.5))
            }
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
              if let selectedData = getSelectedSoilTempData(for: selectedDate) {
                VStack(alignment: .center, spacing: 2) {
                  Text(formatTimeToHHMM(date: selectedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  
                  VStack(alignment: .leading, spacing: 2) {
                    if let temp0 = selectedData.temp0 {
                      HStack(spacing: 4) {
                        Circle().fill(.brown).frame(width: 6, height: 6)
                        Text("\(temp0, specifier: "%.1f")° (0cm)")
                          .font(.caption2)
                          .foregroundStyle(.white)
                      }
                    }
                    
                    if let temp6 = selectedData.temp6 {
                      HStack(spacing: 4) {
                        Circle().fill(.brown.opacity(0.7)).frame(width: 6, height: 6)
                        Text("\(temp6, specifier: "%.1f")° (6cm)")
                          .font(.caption2)
                          .foregroundStyle(.white)
                      }
                    }
                    
                    if let temp18 = selectedData.temp18 {
                      HStack(spacing: 4) {
                        Circle().fill(.brown.opacity(0.5)).frame(width: 6, height: 6)
                        Text("\(temp18, specifier: "%.1f")° (18cm)")
                          .font(.caption2)
                          .foregroundStyle(.white)
                      }
                    }
                    
                    if let temp54 = selectedData.temp54 {
                      HStack(spacing: 4) {
                        Circle().fill(.brown.opacity(0.3)).frame(width: 6, height: 6)
                        Text("\(temp54, specifier: "%.1f")° (54cm)")
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
        "0cm (\(unit))": .brown,
        "6cm (\(unit))": .brown.opacity(0.6),
        "18cm (\(unit))": .brown.opacity(0.4),
        "54cm (\(unit))": .brown.opacity(0.2),
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
  
  /// Gets the nearest soil temperature data for a selected date
  private func getSelectedSoilTempData(for selectedDate: Date) -> (time: Date, temp0: Double?, temp6: Double?, temp18: Double?, temp54: Double?)? {
    return soilTempData.min(by: { abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate)) })
  }
  
  /// Formats time to HH:MM format
  private func formatTimeToHHMM(date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }
}
