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
  
  @State private var selectedDate: Date?

  private var hasNoPrecipitation: Bool {
    precipitation.max() == 0 && snowfall.max() == 0
  }

  private var precipitationData: [(time: Date, precipitation: Double, snowfall: Double)] {
    let count = min(time.count, min(precipitation.count, snowfall.count))
    return (0..<count).map { index in
      (time: Date(timeIntervalSince1970: time[index]),
       precipitation: precipitation[index],
       snowfall: snowfall[index])
    }
  }

  var body: some View {
    if hasNoPrecipitation {
      ContentUnavailableView(
        "Kein Niederschlag", image: "icloud.slash",
        description: Text("Für die nächsten Tage wird kein Niederschlag vorhergesagt.")
      )
      .frame(height: 175)
    } else {
      precipitationChartView
    }
  }

  @ViewBuilder
  private var precipitationChartView: some View {
    VStack(alignment: .leading) {
      Chart {
        ForEach(precipitationData, id: \.time) { data in
          let rainOnly = max(0, data.precipitation - data.snowfall)
          
          if data.snowfall > 0 {
            BarMark(
              x: .value("Hour", data.time),
              y: .value("Schnee (\(unit))", data.snowfall)
            )
            .foregroundStyle(
              .linearGradient(
                colors: [.cyan, .cyan.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
              )
            )
            .cornerRadius(2)
          }
          
          if rainOnly > 0 {
            BarMark(
              x: .value("Hour", data.time),
              y: .value("Regen (\(unit))", rainOnly)
            )
            .foregroundStyle(
              .linearGradient(
                colors: [.blue, .blue.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
              )
            )
            .cornerRadius(2)
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
              if let selectedData = getSelectedPrecipitationData(for: selectedDate) {
                VStack(alignment: .center, spacing: 2) {
                  Text(formatTimeToHHMM(date: selectedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  
                  VStack(alignment: .leading, spacing: 1) {
                    if selectedData.snowfall > 0 {
                      HStack(spacing: 4) {
                        Circle().fill(.cyan).frame(width: 6, height: 6)
                        Text("\(selectedData.snowfall, specifier: "%.1f") \(unit)")
                          .font(.caption2)
                          .foregroundStyle(.white)
                      }
                    }
                    
                    let rainOnly = max(0, selectedData.precipitation - selectedData.snowfall)
                    if rainOnly > 0 {
                      HStack(spacing: 4) {
                        Circle().fill(.blue).frame(width: 6, height: 6)
                        Text("\(rainOnly, specifier: "%.1f") \(unit)")
                          .font(.caption2)
                          .foregroundStyle(.white)
                      }
                    }
                    
                    if selectedData.precipitation == 0 {
                      HStack(spacing: 4) {
                        Circle().fill(.secondary).frame(width: 6, height: 6)
                        Text("0 \(unit)")
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
                .background(.ultraThinMaterial, in: .capsule)
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
      .chartXSelection(value: $selectedDate)
      .frame(height: 175)
    }
  }
  
  /// Gets the nearest precipitation data for a selected date
  private func getSelectedPrecipitationData(for selectedDate: Date) -> (time: Date, precipitation: Double, snowfall: Double)? {
    return precipitationData.min(by: { abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate)) })
  }
  
  /// Formats time to HH:MM format
  private func formatTimeToHHMM(date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }
}
