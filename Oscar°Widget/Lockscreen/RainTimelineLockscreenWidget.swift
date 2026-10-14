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
    let bars: [Double]
    let headline: String
    let spanMinutes: Int
    let hasRadarCoverage: Bool
}

struct RainTimelineProvider: TimelineProvider {
    let client = APIClient.shared

    func placeholder(in context: Context) -> RainTimelineEntry {
        Self.makeEntry(from: Self.placeholderSeries(), now: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (RainTimelineEntry) -> ()) {
        completion(Self.makeEntry(from: Self.placeholderSeries(), now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<RainTimelineEntry>) -> ()) {
        runWidgetTimeline(refreshMinutes: 15, retryMinutes: 10, completion: completion) { coordinates in
            let precipSeries = try await client.getRadarSeries(coordinates: coordinates)
            return nowcastEntryDates(refreshMinutes: 15).map { Self.makeEntry(from: precipSeries, now: $0) }
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

        let points = RainNowcastSummary.points(from: series, now: now)

        guard let last = points.last else {
            return RainTimelineEntry(
                date: now,
                bars: [],
                headline: String(localized: "Radardaten sind veraltet", comment: "LS Widget Regenverlauf mit veralteten Radardaten"),
                spanMinutes: 0,
                hasRadarCoverage: true
            )
        }

        return RainTimelineEntry(
            date: now,
            bars: points.map { max(0, $0.precipitation) },
            headline: RainNowcastSummary.headline(for: points, now: now),
            spanMinutes: max(0, Int((last.timestamp.timeIntervalSince(now) / 60).rounded())),
            hasRadarCoverage: true
        )
    }

    static func placeholderSeries(now: Date = Date()) -> PrecipSeriesResponse {
        let points: [PrecipPoint] = (0..<RainNowcastSummary.maxBars).map { step -> PrecipPoint in
            let timestamp = now.addingTimeInterval(Double(step) * 300)
            let precipitation: Double
            if step < 7 {
                precipitation = 0
            } else {
                precipitation = min(2.4, Double(step - 6) * 0.4)
            }
            let isForecast = step > 2

            return PrecipPoint(timestamp: timestamp, precipitation: precipitation, isForecast: isForecast)
        }
        let response = PrecipSeriesResponse(
            source: "placeholder",
            unit: "mm/h",
            latitude: 0,
            longitude: 0,
            series: points,
            generatedAt: nil,
            lastObservedAt: nil,
            forecastHorizon: nil
        )
        return response
    }
}

struct RainTimelineLockScreenView: View {
    var entry: RainTimelineProvider.Entry
    @Environment(\.widgetFamily) private var family

    @ViewBuilder
    var body: some View {
        switch family {
        case .accessoryRectangular:
            RainTimelineRectangularView(entry: entry)
                .containerBackground(.clear, for: .widget)
        default:
            EmptyView()
                .containerBackground(.clear, for: .widget)
        }
    }
}

private struct RainTimelineRectangularView: View {
    let entry: RainTimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            RainTimelineHeader(entry: entry)
                .widgetAccentable()
            RainTimelineContent(entry: entry)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RainTimelineHeader: View {
    let entry: RainTimelineEntry

    private var iconName: String {
        entry.hasRadarCoverage ? "cloud.rain.fill" : "cloud.slash"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 11))
                .accessibilityHidden(true)
            Text(entry.headline)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct RainTimelineContent: View {
    let entry: RainTimelineEntry

    var body: some View {
        if !entry.hasRadarCoverage {
            Text("Radar ist für diesen Ort nicht verfügbar")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else if !entry.bars.isEmpty {
            RainTimelineBars(bars: entry.bars)
            RainTimelineAxisLabel(spanMinutes: entry.spanMinutes)
        }
    }
}

private struct RainTimelineAxisLabel: View {
    let spanMinutes: Int

    var body: some View {
        HStack {
            Text("Jetzt")
            Spacer()
            Text("+\(spanMinutes) min")
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
    }
}

private struct RainTimelineBars: View {
    let bars: [Double]

    private static let barAreaHeight: CGFloat = 24

    private var reference: Double {
        RainNowcastSummary.reference(for: bars)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(bars.enumerated(), id: \.offset) { _, value in
                RainNowcastBar(
                    value: value, reference: reference, areaHeight: Self.barAreaHeight,
                    fill: value > 0 ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.secondary.opacity(0.35))
                )
            }
        }
        .frame(height: Self.barAreaHeight, alignment: .bottom)
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
