//
//  TemperatureChart.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.08.24.
//

import SwiftUI
import Charts

struct TemperatureChart: View {
    var temperature: [Double]
    var apparentTemperature: [Double]
    var time: [Double]
    var unit: String
    var maxTimeRange: ClosedRange<Date>
    
    var body: some View {
        VStack(alignment: .leading) {
            Chart {
                ForEach(Array(zip(time, temperature).enumerated()), id: \.offset) { index, pair in
                    let (timeValue, temp) = pair
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
                        y: .value("Temperatur (\(unit))", temp),
                        series: .value("Series", "Temperature")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.orange)
                }
                
                ForEach(Array(zip(time, apparentTemperature).enumerated()), id: \.offset) { index, pair in
                    let (timeValue, appTemp) = pair
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
                        y: .value("Gefühlte Temperatur (\(unit))", appTemp),
                        series: .value("Series", "Apparent Temperature")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.red)
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
            .chartForegroundStyleScale([String(localized: "Temperatur") + " (\(unit))": .orange, String(localized: "Gefühlte Temperatur") + " (\(unit))": .red])
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
            .frame(height: 175)
        }
    }
}
