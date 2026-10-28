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
    let speed: Double?
    let directionDegrees: Double?
    let compass: String
}

struct WindProvider: TimelineProvider {
    let client = APIClient.shared

    func placeholder(in context: Context) -> WindLockScreenEntry {
        WindLockScreenEntry(date: Date(), speed: 12, directionDegrees: 45, compass: Self.compassDirection(45))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WindLockScreenEntry) -> ()) {
        completion(WindLockScreenEntry(date: Date(), speed: 12, directionDegrees: 45, compass: Self.compassDirection(45)))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WindLockScreenEntry>) -> ()) {
        runWidgetTimeline(refreshMinutes: 30, completion: completion) { coordinates in
            let weather = try await client.getForecast(
                coordinates: coordinates,
                forecastDays: ._1,
                hourly: [.windspeed_10m]
            )

            let direction = weather.current?.wind_direction_10m

            return [WindLockScreenEntry(
                date: Date(),
                speed: weather.current?.windspeed,
                directionDegrees: direction,
                compass: direction.map(Self.compassDirection) ?? ""
            )]
        }
    }

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
    private var units: Units { SettingService.resolvedUnits }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 11))
                        .rotationEffect(.degrees((entry.directionDegrees ?? 0) + 180))
                        .opacity(entry.directionDegrees == nil ? 0 : 1)
                        .widgetAccentable()
                    Text(speedText)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(units.wind.symbol)
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
        return units.windNumber(speed)
    }

    private var inlineText: String {
        let speed = units.windString(entry.speed)
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
