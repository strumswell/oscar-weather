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
    var gusts: Double? = nil
    var cityID: String? = nil
    var staleNote: String? = nil
    var sky: LinearGradient? = nil
}

struct WindProvider: PlaceTimelineSource {
    let refreshMinutes = 30

    func placeholder(in context: Context) -> WindLockScreenEntry {
        WindLockScreenEntry(date: Date(), speed: 18, directionDegrees: 225, compass: compassDirection(225), gusts: 42)
    }

    func entries(for place: WidgetPlace, family: WidgetFamily) async throws -> [WindLockScreenEntry] {
        let (weather, fetchedAt) = try await WidgetForecast.forecast(place.coordinates)
        let now = Date()
        let direction = weather.current?.wind_direction_10m

        var entry = WindLockScreenEntry(
            date: now,
            speed: weather.current?.windspeed,
            directionDegrees: direction,
            compass: direction.map(compassDirection) ?? "",
            gusts: weather.hourly?.windgusts_10m?[safe: weather.hourIndex(at: now)] ?? nil,
            cityID: place.cityID,
            staleNote: staleText(fetchedAt, at: now, timeZone: weather.locationTimeZone)
        )
        #if os(iOS)
        if family == .systemSmall {
            entry.sky = await WeatherAtmosphericAdapter.widgetGradient(weather: weather, precipSeries: nil, coordinates: place.coordinates)
        }
        #endif
        return [entry]
    }
}

struct WindLockScreenView: View {
    var entry: WindProvider.Entry
    @Environment(\.widgetFamily) private var family
    private var units: Units { SettingService.resolvedUnits }

    var body: some View {
        content
            .widgetURL(.oscarPlace(entry.cityID))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        #if os(iOS)
        case .systemSmall:
            WindDialView(entry: entry)
        #endif
        default:
            accessory
                .containerBackground(.clear, for: .widget)
        }
    }

    @ViewBuilder
    private var accessory: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                WindArrow(degrees: entry.directionDegrees)
                    .font(.system(size: 11))
                Text(speedText)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(units.wind.symbol)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        case .accessoryRectangular:
            WindRectangularView(entry: entry)
        case .accessoryInline:
            HStack {
                Image(systemName: "wind")
                Text(inlineText)
            }
        default:
            EmptyView()
        }
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

private struct WindArrow: View {
    let degrees: Double?

    var body: some View {
        Image(systemName: "location.north.fill")
            .rotationEffect(.degrees((degrees ?? 0) + 180))
            .opacity(degrees == nil ? 0 : 1)
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}

private struct WindRectangularView: View {
    let entry: WindLockScreenEntry
    private var units: Units { SettingService.resolvedUnits }

    private var detail: String? {
        if let stale = entry.staleNote { return stale }
        let gusts = entry.gusts.map { String(localized: "Böen \(units.windNumber($0))", comment: "Widget Wind: Böen ohne Einheit") }
        let from = entry.compass.isEmpty ? nil : String(localized: "aus \(entry.compass)", comment: "Widget Wind: Herkunftsrichtung")
        let parts = [gusts, from].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(.secondary, lineWidth: 1.5)
                WindArrow(degrees: entry.directionDegrees)
                    .font(.system(size: 18))
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(entry.speed.map(units.windNumber) ?? "–")
                        .font(.system(size: 22, weight: .semibold))
                    Text(units.wind.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(windAccessibilityText(entry, units: units))
    }
}

private func windAccessibilityText(_ entry: WindLockScreenEntry, units: Units) -> String {
    var parts = [String(localized: "Wind \(units.windString(entry.speed))", comment: "Widget Wind: Bedienungshilfe Geschwindigkeit")]
    if !entry.compass.isEmpty {
        parts.append(String(localized: "aus \(entry.compass)", comment: "Widget Wind: Herkunftsrichtung"))
    }
    if let gusts = entry.gusts {
        parts.append(String(localized: "Böen \(units.windString(gusts))", comment: "Widget Wind: Böen mit Einheit"))
    }
    return parts.joined(separator: ", ")
}

#if os(iOS)
private struct WindDialView: View {
    let entry: WindLockScreenEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var units: Units { SettingService.resolvedUnits }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Wind")
                Spacer(minLength: 4)
                if !entry.compass.isEmpty {
                    Text("aus \(entry.compass)")
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.25), lineWidth: 1)
                ForEach(0..<4) { quarter in
                    Capsule()
                        .fill(.white.opacity(0.55))
                        .frame(width: 1.5, height: 6)
                        .offset(y: -49)
                        .rotationEffect(.degrees(Double(quarter) * 90))
                }
                Text(verbatim: "N")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(y: -37)
                if let degrees = entry.directionDegrees {
                    WindNeedle()
                        .fill(.white)
                        .rotationEffect(.degrees(degrees + 180))
                        .widgetAccentable()
                }
                VStack(spacing: 0) {
                    Text(entry.speed.map(units.windNumber) ?? "–")
                        .font(.system(size: 24, weight: .semibold))
                    Text(units.wind.symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .frame(width: 104, height: 104)

            if let staleNote = entry.staleNote {
                Text(staleNote)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            } else if let gusts = entry.gusts {
                Text("Böen \(units.windString(gusts))")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .monospacedDigit()
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(windAccessibilityText(entry, units: units))
        .containerBackground(for: .widget) {
            (entry.sky ?? LinearGradient(colors: [.sunriseStart, .sunnyDayEnd], startPoint: .top, endPoint: .bottom))
                .opacity(renderingMode == .accented ? 0 : 1)
        }
    }
}

private struct WindNeedle: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius * 0.74))
        path.addLine(to: CGPoint(x: center.x + 6, y: center.y - radius * 0.48))
        path.addLine(to: CGPoint(x: center.x, y: center.y - radius * 0.54))
        path.addLine(to: CGPoint(x: center.x - 6, y: center.y - radius * 0.48))
        path.closeSubpath()
        path.addRoundedRect(
            in: CGRect(x: center.x - 1, y: center.y + radius * 0.56, width: 2, height: radius * 0.2),
            cornerSize: CGSize(width: 1, height: 1)
        )
        return path
    }
}
#endif

struct WindLockScreenWidget: Widget {
    let kind: String = "WindLockScreenWidget"

    var body: some WidgetConfiguration {
        placeConfiguration(kind: kind, source: WindProvider()) { entry in
            WindLockScreenView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Wind", comment: "LS Widget Wind"))
        .description(String(localized: "Aktuelle Windgeschwindigkeit und Windrichtung", comment: "LS Widget Wind Beschreibung"))
        #if os(iOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
        #else
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

#Preview("Wind", as: .accessoryRectangular) {
    WindLockScreenWidget()
} timeline: {
    WindLockScreenEntry(date: .now, speed: 18, directionDegrees: 225, compass: "SW", gusts: 42)
    WindLockScreenEntry(date: .now, speed: 18, directionDegrees: 225, compass: "SW", gusts: 42, staleNote: staleText(.now.addingTimeInterval(-7200), at: .now))
    WindLockScreenEntry(date: .now, speed: nil, directionDegrees: nil, compass: "")
}

#if os(iOS)
#Preview("Wind S", as: .systemSmall) {
    WindLockScreenWidget()
} timeline: {
    WindLockScreenEntry(date: .now, speed: 18, directionDegrees: 225, compass: "SW", gusts: 42)
    WindLockScreenEntry(date: .now, speed: 4, directionDegrees: 90, compass: "O")
}
#endif
