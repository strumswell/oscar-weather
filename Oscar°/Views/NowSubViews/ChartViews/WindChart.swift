//
//  WindChart.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.08.24.
//

import Charts
import SwiftUI

struct WindChart: View {
  var windspeed10m: [Double]
  var windspeed80m: [Double]
  var windspeed120m: [Double]
  var windspeed180m: [Double]
  var winddirection10m: [Double]
  var time: [Double]
  var unit: String
  var maxTimeRange: ClosedRange<Date>
  
  @State private var selectedDate: Date?

  var windData10m: [(time: Date, speed: Double, direction: Double)] {
    let count = min(time.count, min(windspeed10m.count, winddirection10m.count))
    return (0..<count).map { index in
      (time: Date(timeIntervalSince1970: time[index]), speed: windspeed10m[index], direction: winddirection10m[index])
    }
  }

  var windData80m: [(time: Date, speed: Double)] {
    let count = min(time.count, windspeed80m.count)
    return (0..<count).map { index in
      (time: Date(timeIntervalSince1970: time[index]), speed: windspeed80m[index])
    }
  }

  var windData120m: [(time: Date, speed: Double)] {
    let count = min(time.count, windspeed120m.count)
    return (0..<count).map { index in
      (time: Date(timeIntervalSince1970: time[index]), speed: windspeed120m[index])
    }
  }

  var windData180m: [(time: Date, speed: Double)] {
    let count = min(time.count, windspeed180m.count)
    return (0..<count).map { index in
      (time: Date(timeIntervalSince1970: time[index]), speed: windspeed180m[index])
    }
  }

  var allWindData: [(time: Date, speed10m: Double, direction10m: Double, speed80m: Double, speed120m: Double, speed180m: Double)] {
    let count = min(time.count, min(windspeed10m.count, min(windspeed80m.count, min(windspeed120m.count, min(windspeed180m.count, winddirection10m.count)))))
    return (0..<count).map { index in
      (time: Date(timeIntervalSince1970: time[index]),
       speed10m: windspeed10m[index],
       direction10m: winddirection10m[index], 
       speed80m: windspeed80m[index],
       speed120m: windspeed120m[index],
       speed180m: windspeed180m[index])
    }
  }

  var body: some View {
    VStack(alignment: .leading) {
      Chart {
        // 180m wind speed (lightest)
        ForEach(windData180m, id: \.time) { data in
          LineMark(
            x: .value("Hour", data.time),
            y: .value("Wind 180m (\(unit))", data.speed),
            series: .value("Series", "180m")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.teal.opacity(0.3))
          .lineStyle(.init(lineWidth: 1.5))
        }
        
        // 120m wind speed
        ForEach(windData120m, id: \.time) { data in
          LineMark(
            x: .value("Hour", data.time),
            y: .value("Wind 120m (\(unit))", data.speed),
            series: .value("Series", "120m")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.teal.opacity(0.5))
          .lineStyle(.init(lineWidth: 2))
        }
        
        // 80m wind speed
        ForEach(windData80m, id: \.time) { data in
          LineMark(
            x: .value("Hour", data.time),
            y: .value("Wind 80m (\(unit))", data.speed),
            series: .value("Series", "80m")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.teal.opacity(0.7))
          .lineStyle(.init(lineWidth: 2.5))
        }
        
        // 10m wind speed (clean line without dots)
        ForEach(windData10m, id: \.time) { data in
          LineMark(
            x: .value("Hour", data.time),
            y: .value("Wind 10m (\(unit))", data.speed),
            series: .value("Series", "10m")
          )
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.teal)
          .lineStyle(.init(lineWidth: 3))
        }
        
        // Wind direction indicators (separate marks every 6 hours)
        ForEach(Array(windData10m.enumerated()), id: \.offset) { index, data in
          if index % 6 == 0 {
            PointMark(
              x: .value("Hour", data.time),
              y: .value("Wind 10m (\(unit))", data.speed)
            )
            .symbol {
              Image(systemName: "location.north.fill")
                .resizable()
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(invertWindDirection(data.direction)))
                .foregroundColor(.teal)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
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
              if let selectedData = getSelectedAllWindData(for: selectedDate) {
                VStack(alignment: .center, spacing: 2) {
                  Text(formatTimeToHHMM(date: selectedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  
                  VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                      Circle().fill(.teal).frame(width: 6, height: 6)
                      Image(systemName: "location.north.fill")
                        .resizable()
                        .frame(width: 8, height: 8)
                        .rotationEffect(.degrees(invertWindDirection(selectedData.direction10m)))
                        .foregroundColor(.white)
                      Text("\(selectedData.speed10m, specifier: "%.1f") \(unit) (10m)")
                        .font(.caption2)
                        .foregroundStyle(.white)
                    }
                    
                    HStack(spacing: 4) {
                      Circle().fill(.teal.opacity(0.7)).frame(width: 6, height: 6)
                      Text("\(selectedData.speed80m, specifier: "%.1f") \(unit) (80m)")
                        .font(.caption2)
                        .foregroundStyle(.white)
                    }
                    
                    HStack(spacing: 4) {
                      Circle().fill(.teal.opacity(0.5)).frame(width: 6, height: 6)
                      Text("\(selectedData.speed120m, specifier: "%.1f") \(unit) (120m)")
                        .font(.caption2)
                        .foregroundStyle(.white)
                    }
                    
                    HStack(spacing: 4) {
                      Circle().fill(.teal.opacity(0.3)).frame(width: 6, height: 6)
                      Text("\(selectedData.speed180m, specifier: "%.1f") \(unit) (180m)")
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
        "10m (\(unit))": .teal,
        "80m (\(unit))": .teal.opacity(0.6),
        "120m (\(unit))": .teal.opacity(0.4),
        "180m (\(unit))": .teal.opacity(0.2),
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

  private func invertWindDirection(_ direction: Double) -> Double {
    return (direction + 180).truncatingRemainder(dividingBy: 360)
  }
  
  /// Gets the nearest wind data for a selected date
  private func getSelectedWindData(for selectedDate: Date) -> (time: Date, speed: Double, direction: Double)? {
    return windData10m.min(by: { abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate)) })
  }
  
  /// Gets the nearest comprehensive wind data for a selected date
  private func getSelectedAllWindData(for selectedDate: Date) -> (time: Date, speed10m: Double, direction10m: Double, speed80m: Double, speed120m: Double, speed180m: Double)? {
    return allWindData.min(by: { abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate)) })
  }
  
  /// Formats time to HH:MM format
  private func formatTimeToHHMM(date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }
}
