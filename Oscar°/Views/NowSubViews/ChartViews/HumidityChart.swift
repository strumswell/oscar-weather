//
//  HumidityChart.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.08.24.
//

import Charts
import SwiftUI

struct HumidityChart: View {
  var humidity: [Double]
  var time: [Double]
  var unit: String
  var maxTimeRange: ClosedRange<Date>
  var referenceDate: Date
  
  @State private var selectedDate: Date?

  var humidityData: [(time: Date, humidity: Double)] {
    let count = min(time.count, humidity.count)
    return (0..<count).map { index in
      (time: Date(timeIntervalSince1970: time[index]), humidity: humidity[index])
    }
  }

  private var currentDataPoint: (time: Date, humidity: Double)? {
    humidityData.first(where: { $0.time >= referenceDate }) ?? humidityData.last
  }

  var body: some View {
    VStack(alignment: .leading) {
      Chart {
        if #available(iOS 18, *) {
          // Area plot with gradient for humidity
          AreaPlot(
            humidityData.filter { $0.time >= referenceDate },
            x: .value("Hour", \.time),
            y: .value("Luftfeuchtigkeit (\(unit))", \.humidity)
          )
          .foregroundStyle(
            .linearGradient(
              colors: [.green.opacity(0.4), .green.opacity(0.1)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .interpolationMethod(.catmullRom)
          
          LinePlot(
            humidityData.filter { $0.time <= referenceDate },
            x: .value("Hour", \.time),
            y: .value("Luftfeuchtigkeit (\(unit))", \.humidity),
            series: .value("Series", "Humidity-past")
          )
          .foregroundStyle(.green.opacity(0.42))
          .interpolationMethod(.catmullRom)
          .lineStyle(.init(lineWidth: 2.5, dash: [7, 5]))

          LinePlot(
            humidityData.filter { $0.time >= referenceDate },
            x: .value("Hour", \.time),
            y: .value("Luftfeuchtigkeit (\(unit))", \.humidity),
            series: .value("Series", "Humidity-future")
          )
          .foregroundStyle(.green)
          .interpolationMethod(.catmullRom)
          .lineStyle(.init(lineWidth: 2.5))
        } else {
          // iOS 17 fallback with area marks
          ForEach(Array(zip(time, humidity).enumerated()), id: \.offset) { index, pair in
            let (timeValue, humidityValue) = pair
            AreaMark(
              x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
              y: .value("Luftfeuchtigkeit (\(unit))", humidityValue)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(timeValue < referenceDate.timeIntervalSince1970 ? .green.opacity(0.12) : .green.opacity(0.3))
          }
          
          ForEach(Array(zip(time, humidity).enumerated()), id: \.offset) { index, pair in
            let (timeValue, humidityValue) = pair
            LineMark(
              x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
              y: .value("Luftfeuchtigkeit (\(unit))", humidityValue),
              series: .value("Series", timeValue < referenceDate.timeIntervalSince1970 ? "Humidity-past" : "Humidity-future")
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(timeValue < referenceDate.timeIntervalSince1970 ? .green.opacity(0.42) : .green)
            .lineStyle(timeValue < referenceDate.timeIntervalSince1970 ? .init(lineWidth: 2.5, dash: [7, 5]) : .init(lineWidth: 2.5))
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
              if let selectedData = getSelectedHumidityData(for: selectedDate) {
                VStack(alignment: .center, spacing: 2) {
                  Text(HourlyChartUtilities.timeString(from: selectedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  
                  VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                      Circle().fill(.green).frame(width: 6, height: 6)
                      Text("\(selectedData.humidity, specifier: "%.0f")\(unit)")
                        .font(.caption2)
                        .foregroundStyle(.white)
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
                .background(.ultraThinMaterial, in: .capsule)
            }
        }
      }
      .chartForegroundStyleScale([
        String(localized: "Relative Luftfeuchtigkeit") + " (\(unit))": .green
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
  
  /// Gets the nearest humidity data for a selected date
  private func getSelectedHumidityData(for selectedDate: Date) -> (time: Date, humidity: Double)? {
    return humidityData.min(by: { abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate)) })
  }

  @ChartContentBuilder
  private var currentPointMarks: some ChartContent {
    if let currentDataPoint {
      PointMark(
        x: .value("Current Hour", currentDataPoint.time),
        y: .value("Luftfeuchtigkeit", currentDataPoint.humidity)
      )
      .symbol(.circle)
      .symbolSize(90)
      .foregroundStyle(.black)

      PointMark(
        x: .value("Current Hour", currentDataPoint.time),
        y: .value("Luftfeuchtigkeit", currentDataPoint.humidity)
      )
      .symbol(.circle)
      .symbolSize(42)
      .foregroundStyle(.white)
    }
  }
}
