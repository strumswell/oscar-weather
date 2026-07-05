//
//  UVIndexLockscreenWidget.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 05.07.26.
//

import Foundation
import CoreLocation
import SwiftUI
import WidgetKit

struct UVIndexLockScreenEntry: TimelineEntry {
    let date: Date
    /// Current UV index, nil when the air quality response carried no usable value.
    let uvIndex: Double?
}

struct UVIndexProvider: TimelineProvider {
    let client = APIClient.shared

    func placeholder(in context: Context) -> UVIndexLockScreenEntry {
        UVIndexLockScreenEntry(date: Date(), uvIndex: 6)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (UVIndexLockScreenEntry) -> ()) {
        completion(UVIndexLockScreenEntry(date: Date(), uvIndex: 6))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<UVIndexLockScreenEntry>) -> ()) {
        Task {
            do {
                let coordinates = await MainActor.run {
                    LocationService.shared.update()
                    return LocationService.shared.getCoordinates()
                }

                let air = try await client.getAirQuality(coordinates: coordinates)
                let entry = UVIndexLockScreenEntry(date: Date(), uvIndex: Self.currentUVIndex(from: air, now: Date()))

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

    /// UV index of the hour closest to "now" (times are unixtime like the forecast).
    static func currentUVIndex(
        from air: Operations.getAirQuality.Output.Ok.Body.jsonPayload,
        now: Date
    ) -> Double? {
        guard let times = air.hourly?.time, let values = air.hourly?.uv_index, !times.isEmpty else {
            return nil
        }

        let nowUnix = now.timeIntervalSince1970
        var closestIndex = 0
        var closestDifference = Double.greatestFiniteMagnitude
        for (index, time) in times.enumerated() {
            let difference = abs(time - nowUnix)
            if difference < closestDifference {
                closestDifference = difference
                closestIndex = index
            }
        }

        // uv_index can be shorter than the time array, so index defensively.
        guard values.indices.contains(closestIndex) else { return nil }
        return values[closestIndex]
    }
}

struct UVIndexLockScreenView: View {
    var entry: UVIndexProvider.Entry
    @Environment(\.widgetFamily) private var family

    /// WHO color bands: 0-2 green, 3-5 yellow, 6-7 orange, 8-10 red, 11+ violet.
    private static let uvBands = Gradient(stops: [
        .init(color: .green, location: 0.0),
        .init(color: .green, location: 2.5 / 11.0),
        .init(color: .yellow, location: 2.6 / 11.0),
        .init(color: .yellow, location: 5.5 / 11.0),
        .init(color: .orange, location: 5.6 / 11.0),
        .init(color: .orange, location: 7.5 / 11.0),
        .init(color: .red, location: 7.6 / 11.0),
        .init(color: .red, location: 10.5 / 11.0),
        .init(color: .purple, location: 10.6 / 11.0),
        .init(color: .purple, location: 1.0),
    ])

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: min(max(entry.uvIndex ?? 0, 0), 11), in: 0...11) {
                    Text("UV")
                } currentValueLabel: {
                    Text(valueText)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Self.uvBands)
            case .accessoryInline:
                HStack {
                    Image(systemName: "sun.max.fill")
                    Text(inlineText)
                }
            default:
                EmptyView()
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var valueText: String {
        guard let uvIndex = entry.uvIndex else { return "–" }
        return "\(Int(uvIndex.rounded()))"
    }

    private var inlineText: String {
        guard let uvIndex = entry.uvIndex else {
            return String(localized: "UV-Index –", comment: "LS Widget UV-Index ohne Daten")
        }
        return String(localized: "UV \(Int(uvIndex.rounded())) · \(Self.category(for: uvIndex))", comment: "LS Widget UV-Index inline: Wert und WHO-Kategorie")
    }

    /// WHO exposure categories.
    static func category(for uvIndex: Double) -> String {
        switch Int(uvIndex.rounded()) {
        case ..<3:
            return String(localized: "Niedrig", comment: "UV-Kategorie 0-2")
        case 3...5:
            return String(localized: "Mäßig", comment: "UV-Kategorie 3-5")
        case 6...7:
            return String(localized: "Hoch", comment: "UV-Kategorie 6-7")
        case 8...10:
            return String(localized: "Sehr hoch", comment: "UV-Kategorie 8-10")
        default:
            return String(localized: "Extrem", comment: "UV-Kategorie 11+")
        }
    }
}

struct UVIndexLockScreenWidget: Widget {
    let kind: String = "UVIndexLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UVIndexProvider()) { entry in
            UVIndexLockScreenView(entry: entry)
        }
        .configurationDisplayName(String(localized: "UV-Index", comment: "LS Widget UV-Index"))
        .description(String(localized: "Aktueller UV-Index mit WHO-Farbskala", comment: "LS Widget UV-Index Beschreibung"))
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}
