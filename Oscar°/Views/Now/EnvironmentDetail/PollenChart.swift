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

    /// Builds the series once from the parallel Open-Meteo arrays; types with
    /// no data drop out.
    static func build(
        time: [Double], alder: [Double?], birch: [Double?], grass: [Double?],
        mugwort: [Double?], ragweed: [Double?]
    ) -> [PollenSeries] {
        [
            make(type: .alder, label: String(localized: "Erle"), time: time, values: alder, color: .pink),
            make(type: .birch, label: String(localized: "Birke"), time: time, values: birch, color: .teal),
            make(type: .grass, label: String(localized: "Gräser"), time: time, values: grass, color: .green),
            make(type: .mugwort, label: String(localized: "Beifuß"), time: time, values: mugwort, color: .indigo),
            make(type: .ragweed, label: String(localized: "Ambrosia"), time: time, values: ragweed, color: .brown),
        ]
        .compactMap { $0 }
    }

    private static func make(type: PollenType, label: String, time: [Double], values: [Double?], color: Color) -> PollenSeries? {
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

        return PollenSeries(id: label, type: type, label: label, lineColor: color, points: points)
    }
}

struct PollenChart: View {
    let series: [PollenSeries]
    /// Raw hourly stamps for the day-separator rules.
    let time: [Double]
    let maxTimeRange: ClosedRange<Date>
    let referenceDate: Date

    @State private var selectedDate: Date?

    private var accessibilitySummary: String {
        let loads = series.compactMap { pollenSeries -> String? in
            let peak = pollenSeries.points.map(\.severityFraction).max() ?? 0
            guard peak > 0 else { return nil }
            let tier: String = switch peak {
            case ..<0.5: String(localized: "Gering")
            case ..<0.75: String(localized: "Mäßig")
            case ..<1: String(localized: "Hoch")
            default: String(localized: "Sehr Hoch")
            }
            return "\(pollenSeries.label) \(tier)"
        }
        return loads.isEmpty ? String(localized: "Keine Belastung") : loads.formatted(.list(type: .and))
    }

    private var severityBands: [(lower: Double, upper: Double, color: Color)] {
        [(0, 0.25, .green), (0.25, 0.5, .yellow), (0.5, 0.75, .orange), (0.75, 1, .red)]
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
                ForEach(severityBands.enumerated(), id: \.offset) { _, band in
                    RectangleMark(
                        xStart: .value("Start", maxTimeRange.lowerBound),
                        xEnd: .value("End", maxTimeRange.upperBound),
                        yStart: .value("Min", band.lower),
                        yEnd: .value("Max", band.upper)
                    )
                    .foregroundStyle(band.color.opacity(0.1))
                }

                ForEach(series) { pollenSeries in
                    let past = pollenSeries.points.filter { $0.time <= referenceDate }
                    let future = pollenSeries.points.filter { $0.time >= referenceDate }
                    ForEach(past) { dataPoint in
                        LineMark(
                            x: .value("Hour", dataPoint.time),
                            y: .value(pollenSeries.label, dataPoint.severityFraction),
                            series: .value("Series", segmentSeriesName(label: pollenSeries.label, isPast: true))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(pollenSeries.lineColor.opacity(0.42))
                        .lineStyle(.init(lineWidth: 2.5, dash: [7, 5]))
                    }

                    ForEach(future) { dataPoint in
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
                                    Text(SettingService.formattedTime(selectedRows[0].time))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    ForEach(selectedRows.enumerated(), id: \.offset) { _, row in
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(row.lineColor)
                                                .frame(width: 6, height: 6)

                                            Text("\(row.label): \(row.rawValue, specifier: "%.0f")")
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
                }

                HourlyChartUtilities.daySeparatorMarks(time: time)
            }
            .chartLegend(.hidden)
            .chartXAxis { HourlyChartUtilities.sixHourAxisMarks() }
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
            .chartXSelection(value: .snapped(to: 3600, $selectedDate))
            .frame(height: 240)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Pollenverlauf"))
            .accessibilityValue(accessibilitySummary)

            ChartLegendView(items: series.map { ($0.label, $0.lineColor) }, minimumItemWidth: 82)
        }
    }

    @ChartContentBuilder
    private var currentPointMarks: some ChartContent {
        ForEach(currentSeriesPoints.enumerated(), id: \.offset) { _, point in
            HourlyChartUtilities.currentPointMark(x: point.time, series: point.label, value: point.value)
        }
    }

    private func selectedRows(for selectedDate: Date) -> [(time: Date, label: String, rawValue: Double, lineColor: Color)] {
        series.compactMap { pollenSeries in
            guard let point = pollenSeries.points.min(by: {
                abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate))
            }) else {
                return nil
            }

            return (
                time: point.time,
                label: pollenSeries.label,
                rawValue: point.rawValue,
                lineColor: pollenSeries.lineColor
            )
        }
    }

    private func segmentSeriesName(label: String, isPast: Bool) -> String {
        "\(label)-\(isPast ? "past" : "future")"
    }

}
