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
        runWidgetTimeline(refreshMinutes: 30, completion: completion) { coordinates in
            let air = try await client.getAirQuality(coordinates: coordinates)
            return [UVIndexLockScreenEntry(date: Date(), uvIndex: Self.currentUVIndex(from: air, now: Date()))]
        }
    }

    static func currentUVIndex(
        from air: Operations.getAirQuality.Output.Ok.Body.jsonPayload,
        now: Date
    ) -> Double? {
        guard let times = air.hourly?.time, let values = air.hourly?.uv_index, !times.isEmpty else {
            return nil
        }

        let nowUnix = now.timeIntervalSince1970
        let closestIndex = times.indices.min { abs(times[$0] - nowUnix) < abs(times[$1] - nowUnix) } ?? 0

        guard values.indices.contains(closestIndex) else { return nil }
        return values[closestIndex]
    }
}

struct UVIndexLockScreenView: View {
    var entry: UVIndexProvider.Entry
    @Environment(\.widgetFamily) private var family

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

    static func category(for uvIndex: Double) -> String {
        UVIndexCategory(uvIndex: uvIndex).localizedTitle
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
