//
//  RainView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.
//
import SwiftUI
import Charts

struct RainView: View {
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location
    var openRadarMap: () -> Void = {}

    private var oscarPoints: [PrecipChartPoint] {
        Self.fromNow((weather.precipSeries?.series ?? []).map {
            PrecipChartPoint(date: $0.timestamp, value: $0.precipitation)
        })
    }

    var body: some View {
        if oscarPoints.contains(where: { $0.value > 0 }) {
            VStack(alignment: .leading) {
                Button(action: openRadarMap) {
                    Text("Radar")
                        .font(.system(size: 20))
                        .bold()
                        .foregroundStyle(Color(UIColor.label))
                }
                .buttonStyle(.plain)
                .padding([.leading, .top])

                PrecipitationSeriesChart(points: oscarPoints)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    .background(.thinMaterial)
                    .clipShape(.rect(cornerRadius: 10))
                    .padding([.leading, .trailing, .bottom])
                    .frame(height: 180)
            }
            .scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.8)
                    .scaleEffect(phase.isIdentity ? 1 : 0.99)
                    .blur(radius: phase.isIdentity ? 0 : 0.5)
            }
        }
    }

    /// Keep only the present reading and everything after it — i.e. now → future,
    /// dropping past observations (the series now includes both). Returns empty if
    /// there is no data at/after the current time, so stale data isn't shown.
    private static func fromNow(_ points: [PrecipChartPoint]) -> [PrecipChartPoint] {
        let now = Date()
        let sorted = points.sorted { $0.date < $1.date }
        guard sorted.contains(where: { $0.date >= now }) else { return [] }
        if let startIndex = sorted.lastIndex(where: { $0.date <= now }) {
            return Array(sorted[startIndex...])
        }
        return sorted
    }
}

// MARK: - Reusable precipitation chart

struct PrecipChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double  // mm/h
}

/// Renders the oscar-server precipitation time series (mm/h) as an area chart.
private struct PrecipitationSeriesChart: View {
    let points: [PrecipChartPoint]

    @State private var rawSelectedDate: Date?

    private var maxValue: Double {
        max(points.map(\.value).max() ?? 0, 1)
    }

    private var yAxisValues: [Double] {
        [0, maxValue / 2, maxValue]
    }

    /// Explicit ticks every 30 min starting at the first point: the automatic
    /// axis only labels "nice" round times, which drops the label at the left
    /// edge because the domain starts at the current (non-round) minute.
    private var xAxisValues: [Date] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        return stride(
            from: first.timeIntervalSinceReferenceDate,
            through: last.timeIntervalSinceReferenceDate,
            by: 30 * 60
        ).map(Date.init(timeIntervalSinceReferenceDate:))
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Precipitation", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.7)]),
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }

            if let rawSelectedDate {
                RuleMark(x: .value("Selected", rawSelectedDate, unit: .minute))
                    .foregroundStyle(.gray.opacity(0.3))
                    .annotation(
                        position: .topTrailing, spacing: 0,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        VStack(alignment: .center) {
                            Text(SettingService.formattedTime(rawSelectedDate))
                                .font(.system(size: 11)).foregroundStyle(.gray)
                            VStack {
                                Text(nearestPrecipitation(for: rawSelectedDate))
                                    .bold().foregroundStyle(.blue)
                                Text("mm/h").font(.system(size: 11)).foregroundStyle(.gray)
                                    .padding(.top, -12)
                            }
                        }
                        .padding(6)
                        .background(.ultraThinMaterial.opacity(0.5))
                        .clipShape(.rect(cornerRadius: 7))
                        .shadow(radius: 10)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom, values: xAxisValues) { value in
                AxisTick()
                // Lead-anchor the first label so it renders inside the plot
                // instead of being clipped at the leading edge.
                AxisValueLabel(anchor: value.index == 0 ? .topLeading : .top) {
                    if let date = value.as(Date.self) {
                        Text(SettingService.formattedTime(date))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: yAxisValues) { value in
                AxisGridLine().foregroundStyle(.gray.opacity(0.3))
                AxisValueLabel() {
                    if let value = value.as(Double.self) {
                        Text("\(value, specifier: "%.1f") mm/h")
                    }
                }
            }
        }
        .chartXSelection(value: $rawSelectedDate)
    }

    private func nearestPrecipitation(for date: Date) -> String {
        guard let nearest = points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) else {
            return "No Data"
        }
        return String(format: "%.1f", nearest.value)
    }
}
