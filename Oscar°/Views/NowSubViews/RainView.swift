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

    // Debug: tap the radar chart 5× quickly to spawn a second chart fed by
    // BrightSky `/radar` beneath the primary one, to compare the two services.
    @State private var showBrightskyComparison = false
    @State private var brightskyComparison: Components.Schemas.RadarResponse?

    private var oscarPoints: [PrecipChartPoint] {
        Self.fromNow((weather.precipSeries?.series ?? []).map {
            PrecipChartPoint(date: $0.timestamp, value: $0.precipitation)
        })
    }

    private var brightskyPoints: [PrecipChartPoint] {
        Self.fromNow((brightskyComparison?.radar ?? []).compactMap { data in
            guard let timestamp = data.timestamp,
                  let precipitation = data.precipitation_5?.first?.first else { return nil }
            return PrecipChartPoint(date: timestamp, value: Double(precipitation) / 10.0)
        })
    }

    var body: some View {
        if oscarPoints.contains(where: { $0.value > 0 }) {
            VStack(alignment: .leading) {
                Button(action: openRadarMap) {
                    Text("Radar")
                        .font(.system(size: 20))
                        .bold()
                        .foregroundColor(Color(UIColor.label))
                }
                .buttonStyle(.plain)
                .padding([.leading, .top])

                PrecipitationSeriesChart(points: oscarPoints)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    .background(.thinMaterial)
                    .cornerRadius(10)
                    .padding([.leading, .trailing, .bottom])
                    .frame(height: 180)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture(count: 5).onEnded { toggleBrightskyComparison() }
                    )

                if showBrightskyComparison {
                    Text("BrightSky (Debug)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading)
                    PrecipitationSeriesChart(points: brightskyPoints)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    .background(.thinMaterial)
                    .cornerRadius(10)
                    .padding([.leading, .trailing, .bottom])
                    .frame(height: 180)
                }
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

    private func toggleBrightskyComparison() {
        showBrightskyComparison.toggle()
        UIApplication.shared.playHapticFeedback()
        if showBrightskyComparison, brightskyComparison == nil {
            let coordinates = location.coordinates
            Task {
                brightskyComparison = try? await APIClient.shared.getRainRadar(coordinates: coordinates)
            }
        }
    }
}

// MARK: - Reusable precipitation chart

struct PrecipChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double  // mm/h
}

/// Renders a precipitation time series (mm/h) as an area chart. Used for both the
/// primary oscar-server series and the BrightSky debug comparison.
private struct PrecipitationSeriesChart: View {
    let points: [PrecipChartPoint]

    @State private var rawSelectedDate: Date?

    private var maxValue: Double {
        max(points.map(\.value).max() ?? 0, 1)
    }

    private var yAxisValues: [Double] {
        [0, maxValue / 2, maxValue]
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
                        .cornerRadius(7)
                        .shadow(radius: 10)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisTick()
                AxisValueLabel() {
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
