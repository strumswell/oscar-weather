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
    let points: [PrecipPoint]
    let headline: String
    let hasRadarCoverage: Bool
    let relevance: TimelineEntryRelevance?
    var radarTime: Date? = nil
    var location = ""
    var sky: LinearGradient? = nil
    var cityID: String? = nil
    var timeZone: TimeZone = .current

    var bars: [Double] { RainNowcastSummary.values(points) }
    var rateNow: Double? {
        guard let rate = points.first?.precipitation, rate > 0 else { return nil }
        return rate
    }
    var peak: PrecipPoint? { RainNowcastSummary.peak(in: points) }
}

struct RainTimelineProvider: PlaceTimelineSource {
    let refreshMinutes = 15
    let retryMinutes = 10

    func placeholder(in context: Context) -> RainTimelineEntry {
        var entry = Self.makeEntry(from: Self.series(RainNowcastSummary.sampleComing), now: Date())
        entry.location = "Berlin"
        return entry
    }

    func entries(for place: WidgetPlace, family: WidgetFamily) async throws -> [RainTimelineEntry] {
        let coordinates = place.coordinates
        var series: PrecipSeriesResponse?
        var radarFailed = false
        do {
            series = try await WidgetForecast.radar(coordinates)
        } catch {
            radarFailed = true
        }
        #if os(iOS)
        let isHome = family == .systemSmall || family == .systemMedium
        #else
        let isHome = false
        #endif
        let location = isHome ? await place.locationName() : ""
        let weather = isHome ? (try? await WidgetForecast.forecast(coordinates))?.value : nil
        let timeZone = weather?.locationTimeZone ?? WidgetForecast.cachedTimeZone(coordinates)
        let sky = await skyGradient(weather, series: series, coordinates: coordinates)
        let dates = radarFailed ? [Date()] : nowcastEntryDates(refreshMinutes: refreshMinutes)
        return dates.map { date in
            var entry = radarFailed
                ? Self.emptyEntry(now: date, headline: String(localized: "Radar nicht erreichbar"), hasRadarCoverage: true)
                : Self.makeEntry(from: series, now: date, timeZone: timeZone)
            entry.location = location
            entry.sky = sky
            entry.cityID = place.cityID
            entry.timeZone = timeZone
            return entry
        }
    }

    private func skyGradient(
        _ weather: WidgetForecast.Payload?, series: PrecipSeriesResponse?, coordinates: CLLocationCoordinate2D
    ) async -> LinearGradient? {
        #if os(iOS)
        guard let weather else { return nil }
        return await WeatherAtmosphericAdapter.widgetGradient(weather: weather, precipSeries: series, coordinates: coordinates)
        #else
        return nil
        #endif
    }

    static func makeEntry(from series: PrecipSeriesResponse?, now: Date, timeZone: TimeZone = .current) -> RainTimelineEntry {
        guard let series else {
            return emptyEntry(
                now: now,
                headline: String(localized: "Keine Radardaten", comment: "LS Widget Regenverlauf ohne Radarabdeckung"),
                hasRadarCoverage: false
            )
        }

        let points = RainNowcastSummary.points(from: series, now: now)
        let radarTime = series.series.last { !$0.isForecast }?.timestamp

        guard !points.isEmpty else {
            var entry = emptyEntry(
                now: now,
                headline: String(localized: "Radardaten sind veraltet", comment: "LS Widget Regenverlauf mit veralteten Radardaten"),
                hasRadarCoverage: true
            )
            entry.radarTime = radarTime
            return entry
        }

        let rainWithinHour = points.contains { $0.precipitation > 0 && $0.timestamp <= now.addingTimeInterval(3600) }
        return RainTimelineEntry(
            date: now,
            points: points,
            headline: RainNowcastSummary.headline(for: points, now: now, timeZone: timeZone),
            hasRadarCoverage: true,
            relevance: TimelineEntryRelevance(score: rainWithinHour ? 1 : 0),
            radarTime: radarTime
        )
    }

    static func emptyEntry(now: Date, headline: String, hasRadarCoverage: Bool) -> RainTimelineEntry {
        RainTimelineEntry(
            date: now,
            points: [],
            headline: headline,
            hasRadarCoverage: hasRadarCoverage,
            relevance: TimelineEntryRelevance(score: 0)
        )
    }

    static func series(_ values: [Double], now: Date = Date()) -> PrecipSeriesResponse {
        PrecipSeriesResponse(
            source: "placeholder",
            unit: "mm/h",
            latitude: 0,
            longitude: 0,
            series: RainNowcastSummary.samplePoints(values, now: now),
            generatedAt: nil,
            lastObservedAt: nil,
            forecastHorizon: nil
        )
    }
}

struct RainTimelineWidgetView: View {
    let entry: RainTimelineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(.oscarPlace(entry.cityID))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        #if os(iOS)
        case .systemSmall:
            RainTimelineSmallView(entry: entry)
                .containerBackground(for: .widget) { sky }
        case .systemMedium:
            RainTimelineMediumView(entry: entry)
                .containerBackground(for: .widget) { sky }
        #endif
        case .accessoryInline:
            Label(
                entry.points.isEmpty ? "–" : RainNowcastSummary.shortHeadline(for: entry.points, timeZone: entry.timeZone),
                systemImage: entry.hasRadarCoverage ? "umbrella.fill" : "cloud.slash"
            )
                .containerBackground(.clear, for: .widget)
        default:
            RainTimelineRectangularView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
    }

    private var sky: LinearGradient {
        entry.sky ?? .rainyDay
    }
}

private struct RainTimelineRectangularView: View {
    let entry: RainTimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: entry.hasRadarCoverage ? "cloud.rain.fill" : "cloud.slash")
                    .font(.system(size: 11))
                    .accessibilityHidden(true)
                Text(entry.headline)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .widgetAccentable()
            if !entry.hasRadarCoverage {
                Text("Radar ist für diesen Ort nicht verfügbar")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if !entry.points.isEmpty {
                RainBarsChart(values: entry.bars, height: 24, axis: .span, ceiling: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if os(iOS)
private struct RainTimelineSmallView: View {
    let entry: RainTimelineEntry

    private var header: String {
        [entry.location, entry.radarTime.map { SettingService.formattedTime($0, timeZone: entry.timeZone) }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: header)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
            Text(entry.headline)
                .font(.headline)
            if let subline = RainNowcastSummary.peakText(in: entry.points, withTime: false) {
                Text(subline)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
            RainTimelineChartArea(entry: entry, height: 46, axis: .span)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

private struct RainTimelineMediumView: View {
    let entry: RainTimelineEntry

    private var header: String {
        let radar = entry.radarTime.map { String(localized: "Radar \(SettingService.formattedTime($0, timeZone: entry.timeZone))") }
        return [entry.location, radar]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: header)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(entry.headline)
                        .font(.headline)
                    if let subline = RainNowcastSummary.peakText(in: entry.points, withTime: true, timeZone: entry.timeZone) {
                        Text(subline)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer(minLength: 0)
                if let rate = entry.rateNow {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(RainIntensity.format(rate))
                            .font(.system(size: 30))
                            .monospacedDigit()
                        Text("\(RainIntensity.unit) jetzt")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 6) {
                if entry.hasRadarCoverage {
                    RainScaleLabels(height: 56)
                }
                RainTimelineChartArea(entry: entry, height: 56, axis: .times(start: entry.date, timeZone: entry.timeZone))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

private struct RainTimelineChartArea: View {
    let entry: RainTimelineEntry
    let height: CGFloat
    let axis: RainBarsChart.Axis

    var body: some View {
        if entry.hasRadarCoverage {
            RainBarsChart(values: entry.bars, height: height, axis: axis)
        } else {
            Text("Radar ist für diesen Ort nicht verfügbar")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
        }
    }
}

private struct RainScaleLabels: View {
    let height: CGFloat
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .fullColor {
            ZStack(alignment: .bottomTrailing) {
                ForEach(RainIntensity.gridlines, id: \.self) { value in
                    Text(verbatim: RainIntensity.scaleLabel(value))
                        .offset(y: 5.5 - height * RainIntensity.fraction(value))
                }
            }
            .font(.system(size: 9, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.55))
            .frame(height: height, alignment: .bottomTrailing)
            .accessibilityHidden(true)
        }
    }
}
#endif

struct RainTimelineLockScreenWidget: Widget {
    let kind: String = "RainTimelineLockScreenWidget"

    var body: some WidgetConfiguration {
        placeConfiguration(kind: kind, source: RainTimelineProvider()) { entry in
            RainTimelineWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Regenverlauf", comment: "LS Widget Regenverlauf"))
        .description(String(localized: "Radarbasierter Niederschlag der nächsten 90 Minuten", comment: "LS Widget Regenverlauf Beschreibung"))
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
        #else
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
        #endif
    }
}

private enum RainTimelinePreview {
    static func entry(_ values: [Double]) -> RainTimelineEntry {
        var entry = RainTimelineProvider.makeEntry(from: RainTimelineProvider.series(values), now: .now)
        entry.location = "Leipzig"
        return entry
    }
}

#if os(iOS)
#Preview("Klein", as: .systemSmall) {
    RainTimelineLockScreenWidget()
} timeline: {
    RainTimelinePreview.entry(RainNowcastSummary.sampleComing)
    RainTimelinePreview.entry(Array(repeating: 0, count: 18))
}

#Preview("Mittel", as: .systemMedium) {
    RainTimelineLockScreenWidget()
} timeline: {
    RainTimelinePreview.entry(RainNowcastSummary.sampleRaining)
    RainTimelinePreview.entry(RainNowcastSummary.sampleComing)
    RainTimelinePreview.entry(Array(repeating: 0, count: 18))
}
#endif

#Preview("Sperrbildschirm", as: .accessoryRectangular) {
    RainTimelineLockScreenWidget()
} timeline: {
    RainTimelinePreview.entry(RainNowcastSummary.sampleComing)
    RainTimelinePreview.entry(RainNowcastSummary.sampleRaining)
}

#Preview("Inline", as: .accessoryInline) {
    RainTimelineLockScreenWidget()
} timeline: {
    RainTimelinePreview.entry(RainNowcastSummary.sampleComing)
}
