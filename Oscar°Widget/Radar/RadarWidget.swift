//
//  RadarWidget.swift
//  RadarWidget
//
//  Created by Philipp Bolte on 22.09.20.
//
import AppIntents
import WidgetKit
import SwiftUI

// MARK: - Configuration intent

enum RadarWidgetStyle: String, AppEnum {
    case fiord
    case dark
    case positron

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Kartenstil")
    static let caseDisplayRepresentations: [RadarWidgetStyle: DisplayRepresentation] = [
        .fiord: "Fiord",
        .dark: "Dunkel",
        .positron: "Hell",
    ]
}

struct RadarWidgetConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Regenradar"
    static let description = IntentDescription("Regenradar für deinen Ort")

    @Parameter(title: "Ort")
    var city: WidgetPlaceEntity?

    @Parameter(title: "Kartenstil", default: .fiord)
    var style: RadarWidgetStyle

    @Parameter(title: "Weichzeichnen", default: true)
    var smoothing: Bool

    @Parameter(title: "Bewegungspfeile", default: true)
    var motionArrows: Bool

    @Parameter(title: "Regenzellen", default: false)
    var stormCells: Bool
}

struct RadarWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    var entry: RadarProvider.Entry

    var body: some View {
        HStack(spacing: 0) {
            let map = RadarMapTile(image: entry.image, frameDate: entry.frameDate, isOffline: entry.isOffline, timeZone: entry.timeZone)
            if family == .systemMedium {
                map.aspectRatio(1, contentMode: .fit)
                RadarNowcastPanel(
                    placeName: entry.placeName,
                    headline: entry.headline,
                    bars: entry.bars,
                    forecastStart: entry.forecastStart
                )
            } else {
                map
            }
        }
        .environment(\.colorScheme, .dark)
        .containerBackground(entry.style.mapTone, for: .widget)
        .widgetURL(.oscarRadar(entry.cityID))
    }
}

struct RadarMapTile: View {
    let image: UIImage?
    let frameDate: Date
    let isOffline: Bool
    var timeZone: TimeZone = .current
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if let image {
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .widgetAccentedRenderingMode(.accentedDesaturated)
                        .aspectRatio(contentMode: .fill)
                        .contrast(renderingMode == .accented ? 1.5 : 1)
                }
                .overlay(Color.black.opacity(isOffline ? 0.3 : 0))
                .clipped()
                .overlay(alignment: .topLeading) {
                    RadarTimeBadge(frameDate: frameDate, isOffline: isOffline, timeZone: timeZone)
                }
        } else {
            Text("Radar nicht erreichbar")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct RadarTimeBadge: View {
    let frameDate: Date
    let isOffline: Bool
    var timeZone: TimeZone = .current
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        HStack(spacing: 3) {
            if isOffline {
                Image(systemName: "wifi.slash")
                    .accessibilityLabel(Text("Offline"))
            }
            Text(SettingService.formattedTime(frameDate, timeZone: timeZone))
        }
        .font(.footnote)
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(renderingMode == .accented ? .gray.opacity(0.3) : .gray.opacity(0.6))
        .clipShape(.rect(cornerRadius: 5))
        .widgetAccentable()
        .padding(15)
    }
}

struct RadarNowcastPanel: View {
    let placeName: String
    let headline: String
    let bars: [Double]
    let forecastStart: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(placeName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(headline)
                .font(.subheadline.weight(.semibold))
                .padding(.top, 1)
            if let rate = bars.first, rate > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(RainIntensity.format(rate))
                        .font(.title2)
                        .monospacedDigit()
                    Text("\(RainIntensity.unit) jetzt")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
            if bars.contains(where: { $0 > 0 }) {
                RainBarsChart(values: bars, height: 40, axis: .span)
            } else if let forecastStart {
                Text("Laut Vorhersage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(forecastStart)
                    .font(.headline)
                    .padding(.top, 2)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

extension RadarWidgetStyle {
    var mapTone: LinearGradient {
        let colors: [Color] = switch self {
        case .fiord: [Color(hex: 0x3A4062), Color(hex: 0x23284A)]
        case .dark, .positron: [Color(hex: 0x2A2A2E), Color(hex: 0x161618)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

struct RadarWidget: Widget {
    let kind: String = "WeatherWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: RadarWidgetConfigIntent.self,
            provider: RadarProvider()
        ) { entry in
            RadarWidgetEntryView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName(String(localized: "Regenradar"))
        .description(String(localized: "Regenradar für deinen Ort"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    RadarWidget()
} timeline: {
    RadarProvider.sample()
    RadarEntry(date: .now, frameDate: .now.addingTimeInterval(-3_600), image: UIImage(named: "rain"), isOffline: true)
    RadarEntry(date: .now, frameDate: .now)
}

#Preview("Mittel", as: .systemMedium) {
    RadarWidget()
} timeline: {
    RadarProvider.sample()
    RadarEntry(
        date: .now,
        frameDate: .now,
        image: UIImage(named: "rain"),
        placeName: "Leipzig",
        headline: String(localized: "Kein Regen in Sicht"),
        forecastStart: "Morgen ab 09:00"
    )
}
