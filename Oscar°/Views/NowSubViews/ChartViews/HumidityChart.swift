//
//  HumidityChart.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.08.24.
//

import SwiftUI
import Charts

struct HumidityChart: View {
    var humidity: [Double]
    var time: [Double]
    var unit: String
    var maxTimeRange: ClosedRange<Date>
    
    var body: some View {
        VStack(alignment: .leading) {
            Chart {
                ForEach(Array(zip(time, humidity).enumerated()), id: \.offset) { index, pair in
                    let (timeValue, humidityValue) = pair
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(timeValue))),
                        y: .value("Humidity", humidityValue),
                        series: .value("Series", "Humidity")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.green)
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
            .chartForegroundStyleScale([String(localized: "Relative Luftfeuchtigkeit (\(unit))"): .green])
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
