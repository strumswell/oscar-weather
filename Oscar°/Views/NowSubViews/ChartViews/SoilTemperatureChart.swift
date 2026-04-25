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
  var referenceDate: Date
  
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

  private var currentDataPoint: (time: Date, temp0: Double?, temp6: Double?, temp18: Double?, temp54: Double?)? {
    soilTempData.first(where: { $0.time >= referenceDate }) ?? soilTempData.last
  }

  var body: some View {
    VStack(alignment: .leading) {
      Chart {
        ForEach(soilTempData, id: \.time) { data in
          if let temp54 = data.temp54 {
            soilLineMark(data: data, label: "54cm", value: temp54, color: .brown.opacity(0.3), pastColor: .brown.opacity(0.16), lineWidth: 2)
          }

          if let temp18 = data.temp18 {
            soilLineMark(data: data, label: "18cm", value: temp18, color: .brown.opacity(0.5), pastColor: .brown.opacity(0.24), lineWidth: 2.5)
          }

          if let temp6 = data.temp6 {
            soilLineMark(data: data, label: "6cm", value: temp6, color: .brown.opacity(0.7), pastColor: .brown.opacity(0.34), lineWidth: 3)
          }

          if let temp0 = data.temp0 {
            soilLineMark(data: data, label: "0cm", value: temp0, color: .brown, pastColor: .brown.opacity(0.42), lineWidth: 3.5)
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
              if let selectedData = getSelectedSoilTempData(for: selectedDate) {
                VStack(alignment: .center, spacing: 2) {
                  Text(HourlyChartUtilities.timeString(from: selectedDate))
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

  @ChartContentBuilder
  private func soilLineMark(
    data: (time: Date, temp0: Double?, temp6: Double?, temp18: Double?, temp54: Double?),
    label: String,
    value: Double,
    color: Color,
    pastColor: Color,
    lineWidth: Double
  ) -> some ChartContent {
    let isPast = data.time < referenceDate

    LineMark(
      x: .value("Hour", data.time),
      y: .value("\(label) (\(unit))", value),
      series: .value("Series", "\(label)-\(isPast ? "past" : "future")")
    )
    .interpolationMethod(.catmullRom)
    .foregroundStyle(isPast ? pastColor : color)
    .lineStyle(isPast ? .init(lineWidth: lineWidth, dash: [7, 5]) : .init(lineWidth: lineWidth))
  }

  @ChartContentBuilder
  private var currentPointMarks: some ChartContent {
    if let currentDataPoint {
      if let temp0 = currentDataPoint.temp0 {
        currentPointMark(series: "0cm", value: temp0)
      }
      if let temp6 = currentDataPoint.temp6 {
        currentPointMark(series: "6cm", value: temp6)
      }
      if let temp18 = currentDataPoint.temp18 {
        currentPointMark(series: "18cm", value: temp18)
      }
      if let temp54 = currentDataPoint.temp54 {
        currentPointMark(series: "54cm", value: temp54)
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
