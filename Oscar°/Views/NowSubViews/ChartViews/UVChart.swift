//
//  UVChart.swift
//  Oscar°
//

import Charts
import SwiftUI

struct UVDataPoint: Identifiable {
    let id: Int
    let time: Date
    let value: Double
}

struct UVChart: View {
    var uvIndex: [Double]
    var time: [Double]
    var maxTimeRange: ClosedRange<Date>
    var referenceDate: Date

    @State private var selectedDate: Date?

    private var dataPoints: [UVDataPoint] {
        let count = min(time.count, uvIndex.count)
        return (0..<count).map { index in
            UVDataPoint(
                id: index,
                time: Date(timeIntervalSince1970: time[index]),
                value: uvIndex[index]
            )
        }
    }

    private var maxYValue: Double {
        let highestValue = dataPoints.map(\.value).max() ?? 0
        return max(13, ceil(highestValue))
    }

    private var severityBands: [(lower: Double, upper: Double, color: Color)] {
        [
            (0, 3, .green),
            (3, 6, .yellow),
            (6, 8, .orange),
            (8, 11, .red),
            (11, maxYValue, .purple),
        ]
    }

    private var currentDataPoint: UVDataPoint? {
        dataPoints.first(where: { $0.time >= referenceDate }) ?? dataPoints.last
    }

    var body: some View {
        Chart {
            ForEach(Array(severityBands.enumerated()), id: \.offset) { _, band in
                RectangleMark(
                    xStart: .value("Start", maxTimeRange.lowerBound),
                    xEnd: .value("End", maxTimeRange.upperBound),
                    yStart: .value("Min", band.lower),
                    yEnd: .value("Max", band.upper)
                )
                .foregroundStyle(band.color.opacity(0.1))
            }

            ForEach(dataPoints.filter { $0.time <= referenceDate }) { dataPoint in
                LineMark(
                    x: .value("Hour", dataPoint.time),
                    y: .value(String(localized: "UV-Index"), dataPoint.value),
                    series: .value("Segment", "uv-past")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.white.opacity(0.4))
                .lineStyle(.init(lineWidth: 3, dash: [7, 5]))
            }

            ForEach(dataPoints.filter { $0.time >= referenceDate }) { dataPoint in
                LineMark(
                    x: .value("Hour", dataPoint.time),
                    y: .value(String(localized: "UV-Index"), dataPoint.value),
                    series: .value("Segment", "uv-future")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.white)
                .lineStyle(.init(lineWidth: 3))
            }

            currentPointMarks

            if let selectedDate, let selectedData = selectedDataPoint(for: selectedDate) {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(.gray.opacity(0.35))
                    .lineStyle(.init(lineWidth: 2))
                    .annotation(
                        position: .topTrailing,
                        spacing: 0,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatTimeToHHMM(date: selectedData.time))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("UV: \(selectedData.value, specifier: "%.1f")")
                                .font(.caption2)
                                .foregroundStyle(EnvironmentMetric.forUV(value: selectedData.value).color)
                        }
                        .padding(8)
                        .background(.ultraThinMaterial.opacity(0.9), in: .rect(cornerRadius: 8))
                        .shadow(radius: 4)
                    }
            }

            ForEach(dayChangeIndices(time: time), id: \.self) { index in
                RuleMark(x: .value("Hour", Date(timeIntervalSince1970: time[index])))
                    .foregroundStyle(.gray.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                    .annotation(
                        position: .topTrailing,
                        spacing: 8,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        Text(dayAbbreviation(from: Date(timeIntervalSince1970: time[index])))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: .capsule)
                    }
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) {
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                AxisGridLine()
                AxisTick()
            }
        }
        .chartYAxis {
            AxisMarks(values: [0.0, 3.0, 6.0, 8.0, 11.0]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let numericValue = value.as(Double.self) {
                        Text("\(Int(numericValue))")
                    }
                }
            }
        }
        .chartYScale(domain: 0...maxYValue)
        .chartXScale(domain: maxTimeRange)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: 108_000)
        .chartXSelection(value: $selectedDate)
        .frame(height: 220)
    }

    @ChartContentBuilder
    private var currentPointMarks: some ChartContent {
        if let currentDataPoint {
            PointMark(
                x: .value("Current Hour", currentDataPoint.time),
                y: .value(String(localized: "UV-Index"), currentDataPoint.value)
            )
            .symbol(.circle)
            .symbolSize(90)
            .foregroundStyle(.black)

            PointMark(
                x: .value("Current Hour", currentDataPoint.time),
                y: .value(String(localized: "UV-Index"), currentDataPoint.value)
            )
            .symbol(.circle)
            .symbolSize(42)
            .foregroundStyle(.white)
        }
    }

    private func selectedDataPoint(for selectedDate: Date) -> UVDataPoint? {
        dataPoints.min {
            abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate))
        }
    }

    private func formatTimeToHHMM(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
