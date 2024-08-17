//
//  WindChart.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.08.24.
//

import SwiftUI
import Charts

struct WindChart: View {
    var windspeed10m: [Double]
    var windspeed80m: [Double]
    var windspeed120m: [Double]
    var windspeed180m: [Double]
    var winddirection10m: [Double]
    var time: [Double]
    var unit: String
    var maxTimeRange: ClosedRange<Date>
    
    var body: some View {
        VStack(alignment: .leading) {
            Chart {
                ForEach(Array(zip(time, windspeed10m).enumerated()), id: \.offset) { index, pair in
                    let (timeValue, speed) = pair
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
                        y: .value("Wind 10m (\(unit))", speed),
                        series: .value("Series", "10m")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.teal)
                    .symbol {
                        if index % 6 == 0 && index < winddirection10m.count {
                            Image(systemName: "location.north.fill")
                                .resizable()
                                .frame(width: 10, height: 10)
                                .rotationEffect(.degrees(invertWindDirection(winddirection10m[index])))
                                .foregroundColor(.teal)
                        }
                    }
                }

                ForEach(Array(zip(time, windspeed80m).enumerated()), id: \.offset) { index, pair in
                    let (timeValue, speed) = pair
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
                        y: .value("Wind 80m (\(unit))", speed),
                        series: .value("Series", "80m")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.teal.opacity(0.6))
                }

                ForEach(Array(zip(time, windspeed120m).enumerated()), id: \.offset) { index, pair in
                    let (timeValue, speed) = pair
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
                        y: .value("Wind 120m (\(unit))", speed),
                        series: .value("Series", "120m")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.teal.opacity(0.4))
                }

                ForEach(Array(zip(time, windspeed180m).enumerated()), id: \.offset) { index, pair in
                    let (timeValue, speed) = pair
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
                        y: .value("Wind 180m (\(unit))", speed),
                        series: .value("Series", "180m")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.teal.opacity(0.2))
                }
                
                ForEach(dayChangeIndices(time: time), id: \.self) { index in
                    RuleMark(x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))))
                        .foregroundStyle(.gray)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .annotation(
                            position: .topTrailing, spacing: 5,
                            overflowResolution: .init(
                                x: .fit(to: .chart),
                                y: .fit(to: .chart)
                            )
                        ) {
                            Text(dayAbbreviation(from: Date(timeIntervalSince1970: TimeInterval(time[index]))))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                }
            }
            .chartForegroundStyleScale([
                "10m (\(unit))": .teal,
                "80m (\(unit))": .teal.opacity(0.6),
                "120m (\(unit))": .teal.opacity(0.4),
                "180m (\(unit))": .teal.opacity(0.2)
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
            .frame(height: 200)
        }
    }
    
    private func invertWindDirection(_ direction: Double) -> Double {
        return (direction + 180).truncatingRemainder(dividingBy: 360)
    }
}
