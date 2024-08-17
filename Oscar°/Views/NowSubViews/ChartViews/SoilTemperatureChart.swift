//
//  SoilTemperatureChart.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.08.24.
//

import SwiftUI
import Charts

struct SoilTemperatureChart: View {
    var soilTemp0cm: [Double?]
    var soilTemp6cm: [Double?]
    var soilTemp18cm: [Double?]
    var soilTemp54cm: [Double?]
    var time: [Double]
    var unit: String
    var maxTimeRange: ClosedRange<Date>
    
    var body: some View {
        VStack(alignment: .leading) {
            Chart {
                ForEach(Array(zip(time, soilTemp0cm).enumerated()), id: \.offset) { index, pair in
                    if let tempValue = pair.1 {
                        LineMark(
                            x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(pair.0))),
                            y: .value("0cm", tempValue),
                            series: .value("Series", "Bodentemperatur 0cm (\(unit))")
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.brown)
                    }
                }
                
                ForEach(Array(zip(time, soilTemp6cm).enumerated()), id: \.offset) { index, pair in
                    if let tempValue = pair.1 {
                        LineMark(
                            x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(pair.0))),
                            y: .value("6cm", tempValue),
                            series: .value("Series", "Bodentemperatur 6cm (\(unit))")
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.brown.opacity(0.6))
                    }
                }
                
                ForEach(Array(zip(time, soilTemp18cm).enumerated()), id: \.offset) { index, pair in
                    if let tempValue = pair.1 {
                        LineMark(
                            x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(pair.0))),
                            y: .value("18cm", tempValue),
                            series: .value("Series", "Bodentemperatur 18cm (\(unit))")
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.brown.opacity(0.4))
                    }
                }
                
                ForEach(Array(zip(time, soilTemp54cm).enumerated()), id: \.offset) { index, pair in
                    if let tempValue = pair.1 {
                        LineMark(
                            x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(pair.0))),
                            y: .value("54cm", tempValue),
                            series: .value("Series", "Bodentemperatur 54cm (\(unit))")
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.brown.opacity(0.2))
                    }
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
                "0cm (\(unit))": .brown,
                "6cm (\(unit))": .brown.opacity(0.6),
                "18cm (\(unit))": .brown.opacity(0.4),
                "54cm (\(unit))": .brown.opacity(0.2)
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
}
