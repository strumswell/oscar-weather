//
//  AQIChart.swift
//  Oscar°
//

import Charts
import SwiftUI

struct AQIDataPoint: Identifiable {
    let id: Int
    let time: Date
    let aqi: Double
    let pm25: Double
    let pm10: Double
    let no2: Double
    let o3: Double
    let so2: Double
}

struct AQIChart: View {
    var aqi: [Double]
    var pm25: [Double]
    var pm10: [Double]
    var no2: [Double]
    var o3: [Double]
    var so2: [Double]
    var time: [Double]
    var maxTimeRange: ClosedRange<Date>
    var referenceDate: Date

    @State private var selectedDate: Date?

    private let seriesColors: [String: Color] = [
        "PM2.5": .blue,
        "PM10": .cyan,
        "NO₂": .orange,
        "O₃": .green,
        "SO₂": .yellow,
    ]

    private var dataPoints: [AQIDataPoint] {
        let count = min(
            time.count,
            min(
                aqi.count,
                min(pm25.count, min(pm10.count, min(no2.count, min(o3.count, so2.count))))
            )
        )

        return (0..<count).map { index in
            AQIDataPoint(
                id: index,
                time: Date(timeIntervalSince1970: time[index]),
                aqi: aqi[index],
                pm25: pm25[index],
                pm10: pm10[index],
                no2: no2[index],
                o3: o3[index],
                so2: so2[index]
            )
        }
    }

    private var maxYValue: Double {
        let highestValue = dataPoints
            .map { max($0.pm25, $0.pm10, $0.no2, $0.o3, $0.so2) }
            .max() ?? 100

        return max(120, ceil(highestValue / 20) * 20)
    }

    private var accessibilitySummary: String {
        guard let low = aqi.min(), let high = aqi.max() else { return "" }
        return String(localized: "AQI \(Int(low.rounded())) bis \(Int(high.rounded())), Spitze \(EUAirQualityBand(value: high).localizedStatus)")
    }

    private var severityBands: [(lower: Double, upper: Double, color: Color)] {
        EUAirQualityBand.allCases.map { ($0.lowerBound, $0.upperBound ?? maxYValue, $0.color) }
    }

    private var currentDataPoint: AQIDataPoint? {
        dataPoints.first(where: { $0.time >= referenceDate }) ?? dataPoints.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                severityBandMarks
                seriesMarks
                selectionMark
                HourlyChartUtilities.daySeparatorMarks(time: time)
            }
            .chartLegend(.hidden)
            .chartXAxis { HourlyChartUtilities.sixHourAxisMarks() }
            .chartYAxis {
                AxisMarks(values: stride(from: 0, through: maxYValue, by: 20).map { $0 }) {
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                }
            }
            .chartYScale(domain: 0...maxYValue)
            .chartXScale(domain: maxTimeRange)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 108_000)
            .chartXSelection(value: .snapped(to: 3600, $selectedDate))
            .frame(height: 240)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Luftqualitätsverlauf"))
            .accessibilityValue(accessibilitySummary)

            ChartLegendView(items: [
                ("PM2.5", .blue),
                ("PM10", .cyan),
                ("NO₂", .orange),
                ("O₃", .green),
                ("SO₂", .yellow),
            ])
        }
    }

    @ChartContentBuilder
    private var severityBandMarks: some ChartContent {
        ForEach(Array(severityBands.enumerated()), id: \.offset) { _, band in
            RectangleMark(
                xStart: .value("Start", maxTimeRange.lowerBound),
                xEnd: .value("End", maxTimeRange.upperBound),
                yStart: .value("Min", band.lower),
                yEnd: .value("Max", band.upper)
            )
            .foregroundStyle(band.color.opacity(0.1))
        }
    }

    @ChartContentBuilder
    private var seriesMarks: some ChartContent {
        seriesLineMarks(series: "PM2.5", color: .blue, value: \.pm25)
        seriesLineMarks(series: "PM10", color: .cyan, value: \.pm10)
        seriesLineMarks(series: "NO₂", color: .orange, value: \.no2)
        seriesLineMarks(series: "O₃", color: .green, value: \.o3)
        seriesLineMarks(series: "SO₂", color: .yellow, value: \.so2)
        currentPointMarks
    }

    @ChartContentBuilder
    private var selectionMark: some ChartContent {
        if let selectedDate, let selectedData = selectedDataPoint(for: selectedDate) {
            RuleMark(x: .value("Selected", selectedDate))
                .foregroundStyle(.gray.opacity(0.35))
                .lineStyle(.init(lineWidth: 2))
                .annotation(
                    position: .topTrailing,
                    spacing: 0,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    AQIChartAnnotationView(
                        time: SettingService.formattedTime(selectedData.time),
                        rows: annotationRows(for: selectedData)
                    )
                }
        }
    }

    @ChartContentBuilder
    private func seriesLineMarks(
        series: String,
        color: Color,
        value: KeyPath<AQIDataPoint, Double>
    ) -> some ChartContent {
        ForEach(dataPoints.filter { $0.time <= referenceDate }) { dataPoint in
            LineMark(
                x: .value("Hour", dataPoint.time),
                y: .value(series, dataPoint[keyPath: value]),
                series: .value("Series", segmentSeriesName(series: series, isPast: true))
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(mutedPastColor(color))
            .lineStyle(.init(lineWidth: 2, dash: [7, 5]))
        }

        ForEach(dataPoints.filter { $0.time >= referenceDate }) { dataPoint in
            LineMark(
                x: .value("Hour", dataPoint.time),
                y: .value(series, dataPoint[keyPath: value]),
                series: .value("Series", segmentSeriesName(series: series, isPast: false))
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(color)
            .lineStyle(.init(lineWidth: 2.5))
        }
    }

    @ChartContentBuilder
    private var currentPointMarks: some ChartContent {
        if let currentDataPoint {
            HourlyChartUtilities.currentPointMark(x: currentDataPoint.time, series: "PM2.5", value: currentDataPoint.pm25)
            HourlyChartUtilities.currentPointMark(x: currentDataPoint.time, series: "PM10", value: currentDataPoint.pm10)
            HourlyChartUtilities.currentPointMark(x: currentDataPoint.time, series: "NO₂", value: currentDataPoint.no2)
            HourlyChartUtilities.currentPointMark(x: currentDataPoint.time, series: "O₃", value: currentDataPoint.o3)
            HourlyChartUtilities.currentPointMark(x: currentDataPoint.time, series: "SO₂", value: currentDataPoint.so2)
        }
    }

    private func annotationRows(for dataPoint: AQIDataPoint) -> [(label: String, value: Double, seriesColor: Color)] {
        [
            (
                "PM2.5",
                dataPoint.pm25,
                seriesColors["PM2.5", default: .blue]
            ),
            (
                "PM10",
                dataPoint.pm10,
                seriesColors["PM10", default: .cyan]
            ),
            (
                "NO₂",
                dataPoint.no2,
                seriesColors["NO₂", default: .orange]
            ),
            (
                "O₃",
                dataPoint.o3,
                seriesColors["O₃", default: .green]
            ),
            (
                "SO₂",
                dataPoint.so2,
                seriesColors["SO₂", default: .yellow]
            ),
        ]
    }

    private func selectedDataPoint(for selectedDate: Date) -> AQIDataPoint? {
        dataPoints.min {
            abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate))
        }
    }

    private func mutedPastColor(_ color: Color) -> Color {
        color.opacity(0.42)
    }

    private func segmentSeriesName(series: String, isPast: Bool) -> String {
        "\(series)-\(isPast ? "past" : "future")"
    }

}

private struct AQIChartAnnotationView: View {
    let time: String
    let rows: [(label: String, value: Double, seriesColor: Color)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(time)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    Circle()
                        .fill(row.seriesColor)
                        .frame(width: 6, height: 6)

                    Text("\(row.label): \(Int(row.value))")
                        .font(.caption2)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial.opacity(0.9), in: .rect(cornerRadius: 8))
        .shadow(radius: 4)
    }
}
