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
        UVIndexCategory.allCases.map {
            (lower: $0.range.lowerBound, upper: min($0.range.upperBound, maxYValue), color: $0.color)
        }
    }

    private var currentDataPoint: UVDataPoint? {
        dataPoints.first(where: { $0.time >= referenceDate }) ?? dataPoints.last
    }

    private var accessibilitySummary: String {
        guard let peak = uvIndex.max() else { return "" }
        return String(localized: "UV-Index bis \(Int(peak.rounded())) (\(UVIndexCategory(uvIndex: peak).localizedTitle))")
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
                            Text(SettingService.formattedTime(selectedData.time))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 6, height: 6)

                                Text("UV: \(selectedData.value, specifier: "%.1f")")
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(8)
                        .background(.ultraThinMaterial.opacity(0.9), in: .rect(cornerRadius: 8))
                        .shadow(radius: 4)
                    }
            }

            HourlyChartUtilities.daySeparatorMarks(time: time)
        }
        .chartLegend(.hidden)
        .chartXAxis { HourlyChartUtilities.sixHourAxisMarks() }
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
        .chartXSelection(value: .snapped(to: 3600, $selectedDate))
        .frame(height: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("UV-Index-Verlauf"))
        .accessibilityValue(accessibilitySummary)
    }

    @ChartContentBuilder
    private var currentPointMarks: some ChartContent {
        if let currentDataPoint {
            HourlyChartUtilities.currentPointMark(
                x: currentDataPoint.time, series: String(localized: "UV-Index"), value: currentDataPoint.value
            )
        }
    }

    private func selectedDataPoint(for selectedDate: Date) -> UVDataPoint? {
        dataPoints.min {
            abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate))
        }
    }

}
