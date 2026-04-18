//
//  PollenChart.swift
//  Oscar°
//

import Charts
import SwiftUI

struct PollenDataPoint: Identifiable {
    let id: Int
    let time: Date
    let rawValue: Double
    let severityFraction: Double
}

struct PollenSeries: Identifiable {
    let id: String
    let type: PollenType
    let label: String
    let lineColor: Color
    let points: [PollenDataPoint]
}

struct PollenChart: View {
    var time: [Double]
    var alder: [Double?]
    var birch: [Double?]
    var grass: [Double?]
    var mugwort: [Double?]
    var ragweed: [Double?]
    var maxTimeRange: ClosedRange<Date>
    var referenceDate: Date

    @State private var selectedDate: Date?

    private var series: [PollenSeries] {
        [
            makeSeries(type: .alder, label: String(localized: "Erle"), values: alder, color: .pink),
            makeSeries(type: .birch, label: String(localized: "Birke"), values: birch, color: .teal),
            makeSeries(type: .grass, label: String(localized: "Gräser"), values: grass, color: .green),
            makeSeries(type: .mugwort, label: String(localized: "Beifuß"), values: mugwort, color: .indigo),
            makeSeries(type: .ragweed, label: String(localized: "Ambrosia"), values: ragweed, color: .brown),
        ]
        .compactMap { $0 }
    }

    private var currentSeriesPoints: [(label: String, time: Date, value: Double)] {
        series.compactMap { pollenSeries in
            guard let point = pollenSeries.points.first(where: { $0.time >= referenceDate }) ?? pollenSeries.points.last else {
                return nil
            }

            return (
                label: pollenSeries.label,
                time: point.time,
                value: point.severityFraction
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                RectangleMark(
                    xStart: .value("Start", maxTimeRange.lowerBound),
                    xEnd: .value("End", maxTimeRange.upperBound),
                    yStart: .value("Min", 0.0),
                    yEnd: .value("Max", 0.25)
                )
                .foregroundStyle(.green.opacity(0.1))

                RectangleMark(
                    xStart: .value("Start", maxTimeRange.lowerBound),
                    xEnd: .value("End", maxTimeRange.upperBound),
                    yStart: .value("Min", 0.25),
                    yEnd: .value("Max", 0.5)
                )
                .foregroundStyle(.yellow.opacity(0.1))

                RectangleMark(
                    xStart: .value("Start", maxTimeRange.lowerBound),
                    xEnd: .value("End", maxTimeRange.upperBound),
                    yStart: .value("Min", 0.5),
                    yEnd: .value("Max", 0.75)
                )
                .foregroundStyle(.orange.opacity(0.1))

                RectangleMark(
                    xStart: .value("Start", maxTimeRange.lowerBound),
                    xEnd: .value("End", maxTimeRange.upperBound),
                    yStart: .value("Min", 0.75),
                    yEnd: .value("Max", 1.0)
                )
                .foregroundStyle(.red.opacity(0.1))

                ForEach(series) { pollenSeries in
                    ForEach(pollenSeries.points.filter { $0.time <= referenceDate }) { dataPoint in
                        LineMark(
                            x: .value("Hour", dataPoint.time),
                            y: .value(pollenSeries.label, dataPoint.severityFraction),
                            series: .value("Series", segmentSeriesName(label: pollenSeries.label, isPast: true))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(pollenSeries.lineColor.opacity(0.42))
                        .lineStyle(.init(lineWidth: 2.5, dash: [7, 5]))
                    }

                    ForEach(pollenSeries.points.filter { $0.time >= referenceDate }) { dataPoint in
                        LineMark(
                            x: .value("Hour", dataPoint.time),
                            y: .value(pollenSeries.label, dataPoint.severityFraction),
                            series: .value("Series", segmentSeriesName(label: pollenSeries.label, isPast: false))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(pollenSeries.lineColor)
                        .lineStyle(.init(lineWidth: 2.5))
                    }
                }

                currentPointMarks

                if let selectedDate {
                    RuleMark(x: .value("Selected", selectedDate))
                        .foregroundStyle(.gray.opacity(0.35))
                        .lineStyle(.init(lineWidth: 2))
                        .annotation(
                            position: .topTrailing,
                            spacing: 0,
                            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                        ) {
                            let selectedRows = selectedRows(for: selectedDate)

                            if !selectedRows.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(formatTimeToHHMM(date: selectedRows[0].time))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    ForEach(Array(selectedRows.enumerated()), id: \.offset) { _, row in
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(row.lineColor)
                                                .frame(width: 6, height: 6)

                                            Text("\(row.label): \(row.rawValue, specifier: "%.0f")")
                                                .font(.caption2)
                                                .foregroundStyle(row.severityColor)
                                        }
                                    }
                                }
                                .padding(8)
                                .background(.ultraThinMaterial.opacity(0.9), in: .rect(cornerRadius: 8))
                                .shadow(radius: 4)
                            }
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
                AxisMarks(values: [0.0, 0.25, 0.5, 0.75, 1.0]) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let numericValue = value.as(Double.self) {
                            switch numericValue {
                            case 0:
                                Text("Keine")
                            case 0.25:
                                Text("Gering")
                            case 0.5:
                                Text("Mäßig")
                            case 0.75:
                                Text("Hoch")
                            default:
                                Text("Sehr Hoch")
                            }
                        }
                    }
                }
            }
            .chartYScale(domain: 0...1)
            .chartXScale(domain: maxTimeRange)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 108_000)
            .chartXSelection(value: $selectedDate)
            .frame(height: 240)

            PollenChartLegendView(items: series.map { ($0.label, $0.lineColor) })
        }
    }

    @ChartContentBuilder
    private var currentPointMarks: some ChartContent {
        ForEach(Array(currentSeriesPoints.enumerated()), id: \.offset) { _, point in
            PointMark(
                x: .value("Current Hour", point.time),
                y: .value(point.label, point.value)
            )
            .symbol(.circle)
            .symbolSize(90)
            .foregroundStyle(.black)

            PointMark(
                x: .value("Current Hour", point.time),
                y: .value(point.label, point.value)
            )
            .symbol(.circle)
            .symbolSize(42)
            .foregroundStyle(.white)
        }
    }

    private func makeSeries(type: PollenType, label: String, values: [Double?], color: Color) -> PollenSeries? {
        let count = min(time.count, values.count)
        let points = (0..<count).compactMap { index -> PollenDataPoint? in
            guard let rawValue = values[index] else { return nil }

            return PollenDataPoint(
                id: index,
                time: Date(timeIntervalSince1970: time[index]),
                rawValue: rawValue,
                severityFraction: type.tier(for: rawValue).severityFraction
            )
        }

        guard !points.isEmpty else { return nil }

        return PollenSeries(
            id: label,
            type: type,
            label: label,
            lineColor: color,
            points: points
        )
    }

    private func selectedRows(for selectedDate: Date) -> [(time: Date, label: String, rawValue: Double, lineColor: Color, severityColor: Color)] {
        series.compactMap { pollenSeries in
            guard let point = pollenSeries.points.min(by: {
                abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate))
            }) else {
                return nil
            }

            let severityColor =
                EnvironmentMetric.forPollen(
                    type: pollenSeries.type,
                    label: pollenSeries.label,
                    value: point.rawValue
                )?.color ?? pollenSeries.lineColor

            return (
                time: point.time,
                label: pollenSeries.label,
                rawValue: point.rawValue,
                lineColor: pollenSeries.lineColor,
                severityColor: severityColor
            )
        }
    }

    private func segmentSeriesName(label: String, isPast: Bool) -> String {
        "\(label)-\(isPast ? "past" : "future")"
    }

    private func formatTimeToHHMM(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct PollenChartLegendView: View {
    let items: [(label: String, color: Color)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 12)], alignment: .leading, spacing: 8) {
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
