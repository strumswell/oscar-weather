//
//  WindLockscreenWidget.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 05.07.26.
//

import Foundation
import CoreLocation
import SwiftUI
import WidgetKit

struct WindLockScreenEntry: TimelineEntry {
    let date: Date
    /// Wind speed in the user's unit (already converted to Beaufort when selected).
    let speed: Double?
    let unitLabel: String
    /// Meteorological direction in degrees: where the wind comes FROM.
    let directionDegrees: Double?
    let compass: String
}

struct WindProvider: TimelineProvider {
    let client = APIClient.shared

    func placeholder(in context: Context) -> WindLockScreenEntry {
        WindLockScreenEntry(date: Date(), speed: 12, unitLabel: "km/h", directionDegrees: 45, compass: Self.compassDirection(45))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WindLockScreenEntry) -> ()) {
        completion(WindLockScreenEntry(date: Date(), speed: 12, unitLabel: "km/h", directionDegrees: 45, compass: Self.compassDirection(45)))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WindLockScreenEntry>) -> ()) {
        Task {
            do {
                let coordinates = await MainActor.run {
                    LocationService.shared.update()
                    return LocationService.shared.getCoordinates()
                }

                // windspeed_10m only so the response carries the unit label for the display.
                let weather = try await client.getForecast(
                    coordinates: coordinates,
                    forecastDays: ._1,
                    hourly: [.windspeed_10m]
                )

                let unit = WindSpeedUnit(settingValue: SettingService.resolvedWindSpeedUnit)
                let rawSpeed = weather.current?.windspeed
                // Beaufort is displayed locally: the API delivers km/h in that case (see WindSpeedUnit.apiRawValue).
                let speed = unit.usesBeaufortDisplay ? BeaufortScale.value(forKilometersPerHour: rawSpeed) : rawSpeed
                let unitLabel = unit.usesBeaufortDisplay
                    ? unit.displayUnit
                    : (weather.hourly_units?.windspeed_10m ?? unit.displayUnit)
                let direction = weather.current?.wind_direction_10m

                let entry = WindLockScreenEntry(
                    date: Date(),
                    speed: speed,
                    unitLabel: unitLabel,
                    directionDegrees: direction,
                    compass: direction.map(Self.compassDirection) ?? ""
                )

                let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
                completion(Timeline(entries: [entry], policy: .after(nextUpdateDate)))
            } catch {
                // completion must always be called: a dropped timeline request kills the
                // refresh chain and the widget never updates again. An empty timeline keeps
                // the last rendered entry on screen and retries once the API is back.
                let retryDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
                completion(Timeline(entries: [], policy: .after(retryDate)))
            }
        }
    }

    /// Compass shorthand for a meteorological direction (German letters in the
    /// source language, e.g. 45° → "NO").
    static func compassDirection(_ degrees: Double) -> String {
        let directions = [
            String(localized: "N", comment: "Kompass Nord"),
            String(localized: "NO", comment: "Kompass Nordost"),
            String(localized: "O", comment: "Kompass Ost"),
            String(localized: "SO", comment: "Kompass Südost"),
            String(localized: "S", comment: "Kompass Süd"),
            String(localized: "SW", comment: "Kompass Südwest"),
            String(localized: "W", comment: "Kompass West"),
            String(localized: "NW", comment: "Kompass Nordwest"),
        ]
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        let index = Int((positive + 22.5) / 45.0) % 8
        return directions[index]
    }
}

struct WindLockScreenView: View {
    var entry: WindProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 11))
                        // Degrees say where the wind comes FROM; the arrow should point
                        // where it blows TO.
                        .rotationEffect(.degrees((entry.directionDegrees ?? 0) + 180))
                        .opacity(entry.directionDegrees == nil ? 0 : 1)
                        .widgetAccentable()
                    Text(speedText)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(entry.unitLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            case .accessoryInline:
                HStack {
                    Image(systemName: "wind")
                    Text(inlineText)
                }
            default:
                EmptyView()
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var speedText: String {
        guard let speed = entry.speed else { return "–" }
        return "\(Int(speed.rounded()))"
    }

    private var inlineText: String {
        let speed = WindSpeedFormatter.string(entry.speed, unit: entry.unitLabel)
        guard !entry.compass.isEmpty else { return speed }
        return "\(speed) \(entry.compass)"
    }
}

struct WindLockScreenWidget: Widget {
    let kind: String = "WindLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WindProvider()) { entry in
            WindLockScreenView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Wind", comment: "LS Widget Wind"))
        .description(String(localized: "Aktuelle Windgeschwindigkeit und Windrichtung", comment: "LS Widget Wind Beschreibung"))
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}
