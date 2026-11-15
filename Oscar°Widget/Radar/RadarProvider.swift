import WidgetKit
import SwiftUI
import UIKit

struct RadarEntry: TimelineEntry {
    var date: Date
    var frameDate: Date
    var image: UIImage?
    var isOffline = false
    var style: RadarWidgetStyle = .fiord
    var cityID: String? = nil
    var placeName = ""
    var headline = ""
    var bars: [Double] = []
    var forecastStart: String?
    var timeZone: TimeZone = .current
}

struct RadarProvider: AppIntentTimelineProvider {
    typealias Entry = RadarEntry
    typealias Intent = RadarWidgetConfigIntent

    func placeholder(in context: Context) -> RadarEntry {
        Self.sample()
    }

    func snapshot(for configuration: RadarWidgetConfigIntent, in context: Context) async -> RadarEntry {
        if context.isPreview { return Self.sample() }
        return await buildEntries(configuration: configuration, family: context.family)[0]
    }

    func timeline(for configuration: RadarWidgetConfigIntent, in context: Context) async -> Timeline<RadarEntry> {
        let entries = await buildEntries(configuration: configuration, family: context.family)
        return Timeline(entries: entries, policy: .after(minutesFromNow(15)))
    }

    static func sample(now: Date = Date()) -> RadarEntry {
        let values = RainNowcastSummary.sampleRaining
        return RadarEntry(
            date: now,
            frameDate: now,
            image: UIImage(named: "rain"),
            placeName: "Leipzig",
            headline: RainNowcastSummary.headline(for: RainNowcastSummary.samplePoints(values, now: now), now: now),
            bars: values
        )
    }

    private func buildEntries(
        configuration: RadarWidgetConfigIntent, family: WidgetFamily
    ) async -> [RadarEntry] {
        let style = configuration.style.rawValue
        let place = await widgetPlace(for: configuration.city)
        if place.isFixed {
            WidgetBasemapStore.registerFixedBasemap(style: style, at: place.coordinates)
        } else {
            WidgetBasemapStore.registerRequestedStyle(style)
        }

        let options = RadarWidgetRenderOptions(
            style: style,
            smoothing: configuration.smoothing,
            motionArrows: configuration.motionArrows,
            stormCells: configuration.stormCells,
            fixedPlace: place.isFixed
        )
        let size = family == .systemLarge ? WidgetBasemapStore.largeCompositeSize : WidgetBasemapStore.smallCompositeSize

        async let mapRequest = mapSnapshot(place: place, size: size, options: options)
        let now = Date()
        var entry = RadarEntry(date: now, frameDate: now, style: configuration.style, cityID: place.cityID)
        guard family == .systemMedium else {
            entry.timeZone = WidgetForecast.cachedTimeZone(place.coordinates)
            fill(&entry, map: await mapRequest)
            return [entry]
        }

        async let seriesRequest = WidgetForecast.radar(place.coordinates)
        async let forecastRequest = WidgetForecast.forecast(place.coordinates)
        entry.placeName = await place.locationName()
        fill(&entry, map: await mapRequest)
        let series = try? await seriesRequest
        let forecast = (try? await forecastRequest)?.value
        entry.timeZone = forecast?.locationTimeZone ?? .current

        return nowcastEntryDates(refreshMinutes: 15, now: now).map { date in
            var dated = entry
            dated.date = date
            let points = RainNowcastSummary.points(from: series, now: date)
            dated.bars = RainNowcastSummary.values(points)
            dated.headline = points.isEmpty
                ? String(localized: "Keine Radardaten")
                : RainNowcastSummary.headline(for: points, now: date, timeZone: entry.timeZone)
            if !dated.bars.contains(where: { $0 > 0 }), let forecast {
                dated.forecastStart = Self.forecastRainStart(in: forecast, after: date)
            }
            return dated
        }
    }

    private func fill(_ entry: inout RadarEntry, map: RadarMapSnapshot?) {
        guard let map else { return }
        entry.image = map.image
        entry.frameDate = map.frameDate
        entry.isOffline = map.isOffline
    }

    private struct StoredRadarImage: Codable, Sendable {
        let jpeg: Data
        let frameDate: Date
    }

    private struct RadarMapSnapshot {
        let image: UIImage
        let frameDate: Date
        let isOffline: Bool
    }

    private func mapSnapshot(
        place: WidgetPlace, size: CGSize, options: RadarWidgetRenderOptions
    ) async -> RadarMapSnapshot? {
        let kind = "radar-image-\(options.style)-\(Int(size.width))x\(Int(size.height))"
        let started = Date()
        guard let stored = try? await WidgetCache.fetch(WidgetCache.key(kind, place.coordinates), fetch: {
            guard let rendered = await RadarSnapshotRenderer.render(center: place.coordinates, size: size, options: options),
                  let jpeg = rendered.image.jpegData(compressionQuality: 0.85)
            else { throw URLError(.cannotLoadFromNetwork) }
            return StoredRadarImage(jpeg: jpeg, frameDate: rendered.frameDate ?? started)
        }),
              let image = UIImage(data: stored.value.jpeg, scale: RadarSnapshotRenderer.compositeScale)
        else { return nil }
        return RadarMapSnapshot(image: image, frameDate: stored.value.frameDate, isOffline: stored.fetchedAt < started)
    }

    private static func forecastRainStart(
        in forecast: Operations.getForecast.Output.Ok.Body.jsonPayload, after now: Date
    ) -> String? {
        guard let times = forecast.hourly?.time, let amounts = forecast.hourly?.precipitation else { return nil }
        let earliest = now.addingTimeInterval(RainNowcastSummary.horizon)
        let latest = now.addingTimeInterval(3 * 86_400)
        let starts = zip(times, amounts)
            .filter { $0.1 > 0 }
            .map { Date(timeIntervalSince1970: $0.0 - 3600) }
        guard let start = starts.first(where: { $0 >= earliest && $0 <= latest }) else { return nil }

        let timeZone = forecast.locationTimeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day: String
        if calendar.isDate(start, inSameDayAs: now) {
            day = String(localized: "Heute")
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(start, inSameDayAs: tomorrow) {
            day = String(localized: "Morgen")
        } else {
            day = SettingService.formattedShortWeekday(start, timeZone: timeZone)
        }
        return String(localized: "\(day) ab \(SettingService.formattedTime(start, timeZone: timeZone))")
    }
}
