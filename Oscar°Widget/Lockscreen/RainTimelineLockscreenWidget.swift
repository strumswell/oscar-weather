//
//  RainTimelineLockscreenWidget.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 05.07.26.
//

import Foundation
import CoreLocation
import SwiftUI
import WidgetKit

struct RainTimelineEntry: TimelineEntry {
    let date: Date
    /// Precipitation (mm/h) per radar step covering the next ~90 minutes.
    let bars: [Double]
    let headline: String
    /// Minutes between "now" and the last bar, for the axis label.
    let spanMinutes: Int
    let hasRadarCoverage: Bool
}

struct RainTimelineProvider: TimelineProvider {
    let client = APIClient.shared

    static let horizon: TimeInterval = 90 * 60
    static let maxBars = 18

    func placeholder(in context: Context) -> RainTimelineEntry {
        Self.makeEntry(from: Self.placeholderSeries(), now: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (RainTimelineEntry) -> ()) {
        completion(Self.makeEntry(from: Self.placeholderSeries(), now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<RainTimelineEntry>) -> ()) {
        Task {
            do {
                let coordinates = await MainActor.run {
                    LocationService.shared.update()
                    return LocationService.shared.getCoordinates()
                }

                // nil = server successfully reported no radar coverage here.
                let precipSeries = try await client.getRadarSeries(coordinates: coordinates)
                let entry = Self.makeEntry(from: precipSeries, now: Date())

                // Radar nowcasts go stale fast, refresh more often than the other widgets.
                let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
                completion(Timeline(entries: [entry], policy: .after(nextUpdateDate)))
            } catch {
                // completion must always be called: a dropped timeline request kills the
                // refresh chain and the widget never updates again. An empty timeline keeps
                // the last rendered entry on screen and retries once the API is back.
                let retryDate = Calendar.current.date(byAdding: .minute, value: 10, to: Date())!
                completion(Timeline(entries: [], policy: .after(retryDate)))
            }
        }
    }

    static func makeEntry(from series: PrecipSeriesResponse?, now: Date) -> RainTimelineEntry {
        guard let series else {
            return RainTimelineEntry(
                date: now,
                bars: [],
                headline: String(localized: "Keine Radardaten", comment: "LS Widget Regenverlauf ohne Radarabdeckung"),
                spanMinutes: 0,
                hasRadarCoverage: false
            )
        }

        // One radar step of slack into the past so the bar for "now" survives
        // the 5-min cadence; everything else is the upcoming window.
        let points = series.series
            .filter { $0.timestamp > now.addingTimeInterval(-150) && $0.timestamp <= now.addingTimeInterval(Self.horizon) }
            .sorted { $0.timestamp < $1.timestamp }
            .prefix(Self.maxBars)

        guard let last = points.last else {
            // Series exists but has no usable frames around "now" (stale data).
            return RainTimelineEntry(
                date: now,
                bars: [],
                headline: String(localized: "Keine Radardaten", comment: "LS Widget Regenverlauf ohne Radarabdeckung"),
                spanMinutes: 0,
                hasRadarCoverage: false
            )
        }

        return RainTimelineEntry(
            date: now,
            bars: points.map { max(0, $0.precipitation) },
            headline: headline(for: Array(points), now: now),
            spanMinutes: max(0, Int((last.timestamp.timeIntervalSince(now) / 60).rounded())),
            hasRadarCoverage: true
        )
    }

    static func headline(for points: [PrecipPoint], now: Date) -> String {
        let isRainingNow = (points.first?.precipitation ?? 0) > 0

        if isRainingNow {
            if let end = points.first(where: { $0.precipitation <= 0 }) {
                let minutes = max(5, Int((end.timestamp.timeIntervalSince(now) / 60).rounded()))
                if minutes <= 60 {
                    return String(localized: "Regen · noch ~\(minutes) min", comment: "LS Widget Regenverlauf: Regen endet in X Minuten")
                }
                return String(localized: "Regen bis \(SettingService.formattedTime(end.timestamp))", comment: "LS Widget Regenverlauf: Regen endet um Uhrzeit")
            }
            let minutes = max(5, Int((points.last!.timestamp.timeIntervalSince(now) / 60).rounded()))
            return String(localized: "Regen · noch >\(minutes) min", comment: "LS Widget Regenverlauf: Regen hält länger als das Radarfenster an")
        }

        if let start = points.first(where: { $0.precipitation > 0 }) {
            return String(localized: "Regen ab \(SettingService.formattedTime(start.timestamp))", comment: "LS Widget Regenverlauf: Regen beginnt um Uhrzeit")
        }
        return String(localized: "Kein Regen in Sicht", comment: "LS Widget Regenverlauf: kein Regen im Radarfenster")
    }

    /// Synthetic series for placeholder/snapshot: dry now, rain starting mid-window.
    static func placeholderSeries(now: Date = Date()) -> PrecipSeriesResponse {
        let points = (0..<maxBars).map { step in
            PrecipPoint(
                timestamp: now.addingTimeInterval(Double(step) * 300),
                precipitation: step < 7 ? 0 : min(2.4, Double(step - 6) * 0.4),
                isForecast: step > 2
            )
        }
        return PrecipSeriesResponse(
            source: "placeholder",
            unit: "mm/h",
            latitude: 0,
            longitude: 0,
            series: points,
            generatedAt: nil,
            lastObservedAt: nil,
            forecastHorizon: nil
        )
    }
}

struct RainTimelineLockScreenView: View {
    var entry: RainTimelineProvider.Entry
    @Environment(\.widgetFamily) private var family

    private static let barAreaHeight: CGFloat = 24

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: entry.hasRadarCoverage ? "cloud.rain.fill" : "cloud.slash")
                            .font(.system(size: 11))
                        Text(entry.headline)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .widgetAccentable()
                    if entry.hasRadarCoverage {
                        bars
                        HStack {
                            Text("Jetzt")
                            Spacer()
                            Text("+\(entry.spanMinutes) min")
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Radar ist für diesen Ort nicht verfügbar")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                EmptyView()
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var bars: some View {
        // Scale against at least "moderate rain" so drizzle doesn't fill the chart.
        let reference = max(2.0, entry.bars.max() ?? 0)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(entry.bars.enumerated()), id: \.offset) { _, value in
                Capsule(style: .continuous)
                    .fill(value > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(height: barHeight(value, reference: reference))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Self.barAreaHeight, alignment: .bottom)
    }

    private func barHeight(_ value: Double, reference: Double) -> CGFloat {
        guard value > 0 else { return 3 }
        // Square root emphasizes light rain, which is what matters at a glance.
        let fraction = min(1.0, (value / reference).squareRoot())
        return 4 + CGFloat(fraction) * (Self.barAreaHeight - 4)
    }
}

struct RainTimelineLockScreenWidget: Widget {
    let kind: String = "RainTimelineLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RainTimelineProvider()) { entry in
            RainTimelineLockScreenView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Regenverlauf", comment: "LS Widget Regenverlauf"))
        .description(String(localized: "Radarbasierter Niederschlag der nächsten 90 Minuten", comment: "LS Widget Regenverlauf Beschreibung"))
        .supportedFamilies([.accessoryRectangular])
    }
}
