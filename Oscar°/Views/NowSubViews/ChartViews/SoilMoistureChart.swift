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
  var referenceDate: Date
  
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

  private var currentDataPoint: (time: Date, moisture0_1: Double?, moisture1_3: Double?, moisture3_9: Double?, moisture9_27: Double?, moisture27_81: Double?)? {
    soilMoistureData.first(where: { $0.time >= referenceDate }) ?? soilMoistureData.last
  }

  var body: some View {
    VStack(alignment: .leading) {
      Chart {
        ForEach(soilMoistureData, id: \.time) { data in
          if let moisture0_1 = data.moisture0_1 {
            soilLineMark(data: data, label: "0-1cm", value: moisture0_1, color: .brown, pastColor: .brown.opacity(0.42), lineWidth: 2)
          }

          if let moisture1_3 = data.moisture1_3 {
            soilLineMark(data: data, label: "1-3cm", value: moisture1_3, color: .brown.opacity(0.6), pastColor: .brown.opacity(0.3), lineWidth: 2)
          }

          if let moisture3_9 = data.moisture3_9 {
            soilLineMark(data: data, label: "3-9cm", value: moisture3_9, color: .brown.opacity(0.4), pastColor: .brown.opacity(0.22), lineWidth: 2)
          }

          if let moisture9_27 = data.moisture9_27 {
            soilLineMark(data: data, label: "9-27cm", value: moisture9_27, color: .brown.opacity(0.2), pastColor: .brown.opacity(0.13), lineWidth: 2)
          }

          if let moisture27_81 = data.moisture27_81 {
            soilLineMark(data: data, label: "27-81cm", value: moisture27_81, color: .brown.opacity(0.1), pastColor: .brown.opacity(0.08), lineWidth: 2)
          }
        }

        currentPointMarks
        
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
                  Text(HourlyChartUtilities.timeString(from: selectedDate))
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
                .clipShape(.rect(cornerRadius: 8))
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
              Text(HourlyChartUtilities.dayAbbreviation(from: Date(timeIntervalSince1970: TimeInterval(time[index]))))
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary.opacity(0.7))
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

  @ChartContentBuilder
  private func soilLineMark(
    data: (time: Date, moisture0_1: Double?, moisture1_3: Double?, moisture3_9: Double?, moisture9_27: Double?, moisture27_81: Double?),
    label: String,
    value: Double,
    color: Color,
    pastColor: Color,
    lineWidth: Double
  ) -> some ChartContent {
    let isPast = data.time < referenceDate

    LineMark(
      x: .value("Hour", data.time),
      y: .value(label, value),
      series: .value("Series", "\(label)-\(isPast ? "past" : "future")")
    )
    .interpolationMethod(.catmullRom)
    .foregroundStyle(isPast ? pastColor : color)
    .lineStyle(isPast ? .init(lineWidth: lineWidth, dash: [7, 5]) : .init(lineWidth: lineWidth))
  }

  @ChartContentBuilder
  private var currentPointMarks: some ChartContent {
    if let currentDataPoint {
      if let moisture0_1 = currentDataPoint.moisture0_1 {
        currentPointMark(series: "0-1cm", value: moisture0_1)
      }
      if let moisture1_3 = currentDataPoint.moisture1_3 {
        currentPointMark(series: "1-3cm", value: moisture1_3)
      }
      if let moisture3_9 = currentDataPoint.moisture3_9 {
        currentPointMark(series: "3-9cm", value: moisture3_9)
      }
      if let moisture9_27 = currentDataPoint.moisture9_27 {
        currentPointMark(series: "9-27cm", value: moisture9_27)
      }
      if let moisture27_81 = currentDataPoint.moisture27_81 {
        currentPointMark(series: "27-81cm", value: moisture27_81)
      }
    }
  }

  @ChartContentBuilder
  private func currentPointMark(series: String, value: Double) -> some ChartContent {
    if let currentDataPoint {
      PointMark(
        x: .value("Current Hour", currentDataPoint.time),
        y: .value(series, value)
      )
      .symbol(.circle)
      .symbolSize(90)
      .foregroundStyle(.black)

      PointMark(
        x: .value("Current Hour", currentDataPoint.time),
        y: .value(series, value)
      )
      .symbol(.circle)
      .symbolSize(42)
      .foregroundStyle(.white)
    }
  }
}
