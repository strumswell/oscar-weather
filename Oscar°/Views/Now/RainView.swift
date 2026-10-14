//
//  RainView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 24.10.20.
//
import SwiftUI
import Charts

struct RainView: View {
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var openRadarMap: () -> Void = {}

    private var oscarPoints: [PrecipChartPoint] {
        Self.fromNow((weather.precipSeries?.series ?? []).map {
            PrecipChartPoint(date: $0.timestamp, value: $0.precipitation)
        })
    }

    var body: some View {
        let points = oscarPoints
        let hasRain = points.contains(where: { $0.value > 0 })
        if hasRain {
            VStack(alignment: .leading) {
                NowSectionHeader(showMore: openRadarMap) {
                    Text("Radar")
                }

                PrecipitationSeriesChart(points: points, timeZone: weather.forecast.locationTimeZone)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    .cardBackground()
                    .clipShape(.rect(cornerRadius: 10))
                    .cardBorder()
                    .padding([.leading, .trailing, .bottom])
                    .frame(height: 180)
                    .contentShape(.rect)
                    .simultaneousGesture(TapGesture().onEnded { openRadarMap() })
            }
            .scrollTransition { [reduceMotion] content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.8)
                    .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.99)
            }
        }
    }

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
    var id: Date { date }
    let date: Date
    let value: Double  // mm/h
}

struct PrecipitationSeriesChart: View {
    let points: [PrecipChartPoint]
    let timeZone: TimeZone

    @State private var rawSelectedDate: Date?

    private var maxValue: Double {
        max(points.map(\.value).max() ?? 0, 1)
    }

    private var yAxisValues: [Double] {
        [0, maxValue / 2, maxValue]
    }

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
                        gradient: Gradient(colors: [Color.white, Color.white.opacity(0.3)]),
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .alignsMarkStylesWithPlotArea()
            }

            if let rawSelectedDate {
                RuleMark(x: .value("Selected", rawSelectedDate, unit: .minute))
                    .foregroundStyle(.gray.opacity(0.3))
                    .annotation(
                        position: .topTrailing, spacing: 0,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        VStack(alignment: .center) {
                            Text(SettingService.formattedTime(rawSelectedDate, timeZone: timeZone))
                                .font(.caption2).foregroundStyle(.white.opacity(0.72))
                            VStack {
                                Text(nearestPrecipitation(for: rawSelectedDate))
                                    .bold().foregroundStyle(.white)
                                Text("mm/h").font(.caption2).foregroundStyle(.white.opacity(0.72))
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
                AxisValueLabel(anchor: value.index == 0 ? .topLeading : .top) {
                    if let date = value.as(Date.self) {
                        Text(SettingService.formattedTime(date, timeZone: timeZone))
                            .foregroundStyle(.white.opacity(0.72))
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
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }
        }
        .chartXSelection(value: $rawSelectedDate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Regenradar"))
    }

    private func nearestPrecipitation(for date: Date) -> String {
        guard let nearest = points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) else {
            return String(localized: "Keine Daten")
        }
        return nearest.value.formatted(.number.precision(.fractionLength(1)))
    }
}
