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

    /// Zips the parallel Open-Meteo arrays once; the chart body only iterates.
    static func points(
        time: [Double], aqi: [Double], pm25: [Double], pm10: [Double],
        no2: [Double], o3: [Double], so2: [Double]
    ) -> [AQIDataPoint] {
        let count = [time.count, aqi.count, pm25.count, pm10.count, no2.count, o3.count, so2.count].min() ?? 0
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
}

struct AQIChart: View {
    let points: [AQIDataPoint]
    /// Raw hourly stamps for the day-separator rules.
    let time: [Double]
    let maxTimeRange: ClosedRange<Date>
    let referenceDate: Date

    @State private var selectedDate: Date?

    private let seriesColors: [String: Color] = [
        "PM2.5": .blue,
        "PM10": .cyan,
        "NO₂": .orange,
        "O₃": .green,
        "SO₂": .yellow,
    ]

    private var maxYValue: Double {
        let highestValue = points
            .map { max($0.pm25, $0.pm10, $0.no2, $0.o3, $0.so2) }
            .max() ?? 100

        return max(120, ceil(highestValue / 20) * 20)
    }

    private var accessibilitySummary: String {
        let aqi = points.map(\.aqi)
        guard let low = aqi.min(), let high = aqi.max() else { return "" }
        return String(localized: "AQI \(Int(low.rounded())) bis \(Int(high.rounded())), Spitze \(EUAirQualityBand(value: high).localizedStatus)")
    }

    private var severityBands: [(lower: Double, upper: Double, color: Color)] {
        EUAirQualityBand.allCases.map { ($0.lowerBound, $0.upperBound ?? maxYValue, $0.color) }
    }

    private var currentDataPoint: AQIDataPoint? {
        points.first(where: { $0.time >= referenceDate }) ?? points.last
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
        ForEach(severityBands.enumerated(), id: \.offset) { _, band in
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
        let past = points.filter { $0.time <= referenceDate }
        let future = points.filter { $0.time >= referenceDate }
        seriesLineMarks(past: past, future: future, series: "PM2.5", color: .blue, value: \.pm25)
        seriesLineMarks(past: past, future: future, series: "PM10", color: .cyan, value: \.pm10)
        seriesLineMarks(past: past, future: future, series: "NO₂", color: .orange, value: \.no2)
        seriesLineMarks(past: past, future: future, series: "O₃", color: .green, value: \.o3)
        seriesLineMarks(past: past, future: future, series: "SO₂", color: .yellow, value: \.so2)
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
        past: [AQIDataPoint],
        future: [AQIDataPoint],
        series: String,
        color: Color,
        value: KeyPath<AQIDataPoint, Double>
    ) -> some ChartContent {
        ForEach(past) { dataPoint in
            LineMark(
                x: .value("Hour", dataPoint.time),
                y: .value(series, dataPoint[keyPath: value]),
                series: .value("Series", segmentSeriesName(series: series, isPast: true))
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(mutedPastColor(color))
            .lineStyle(.init(lineWidth: 2, dash: [7, 5]))
        }

        ForEach(future) { dataPoint in
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
        points.min {
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

            ForEach(rows.enumerated(), id: \.offset) { _, row in
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
