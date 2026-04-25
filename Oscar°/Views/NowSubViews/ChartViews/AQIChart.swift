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

    private var severityBands: [(lower: Double, upper: Double, color: Color)] {
        [
            (0, 20, Color(red: 79 / 255, green: 240 / 255, blue: 230 / 255)),
            (20, 40, Color(red: 81 / 255, green: 204 / 255, blue: 170 / 255)),
            (40, 60, Color(red: 240 / 255, green: 230 / 255, blue: 65 / 255)),
            (60, 80, Color(red: 255 / 255, green: 81 / 255, blue: 80 / 255)),
            (80, 100, Color(red: 150 / 255, green: 1 / 255, blue: 50 / 255)),
            (100, maxYValue, Color(red: 125 / 255, green: 33 / 255, blue: 129 / 255)),
        ]
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
                daySeparatorMarks
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
            .chartXSelection(value: $selectedDate)
            .frame(height: 240)

            AQIChartLegendView(items: [
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
                        time: formatTimeToHHMM(date: selectedData.time),
                        rows: annotationRows(for: selectedData)
                    )
                }
        }
    }

    @ChartContentBuilder
    private var daySeparatorMarks: some ChartContent {
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
            currentPointMark(
                series: "PM2.5",
                value: currentDataPoint.pm25
            )
            currentPointMark(
                series: "PM10",
                value: currentDataPoint.pm10
            )
            currentPointMark(
                series: "NO₂",
                value: currentDataPoint.no2
            )
            currentPointMark(
                series: "O₃",
                value: currentDataPoint.o3
            )
            currentPointMark(
                series: "SO₂",
                value: currentDataPoint.so2
            )
        }
    }

    @ChartContentBuilder
    private func currentPointMark(series: String, value: Double) -> some ChartContent {
        if let currentDataPoint {
            PointMark(
                x: .value("Current Hour", currentDataPoint.time),
                y: .value(series, value)
            )
            .symbol(.circle)
            .symbolSize(90)
            .foregroundStyle(.black)

            PointMark(
                x: .value("Current Hour", currentDataPoint.time),
                y: .value(series, value)
            )
            .symbol(.circle)
            .symbolSize(42)
            .foregroundStyle(.white)
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

    private func formatTimeToHHMM(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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

private struct AQIChartLegendView: View {
    let items: [(label: String, color: Color)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 12)], alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 8, height: 8)

                    Text(verbatim: item.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
