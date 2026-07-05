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

/// Raw values must match MapBasemapStyle — they key the app-prerendered
/// basemaps in the app group (WidgetBasemapStore).
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
    static let description = IntentDescription("Regenradar für aktuellen Standort")

    @Parameter(title: "Kartenstil", default: .fiord)
    var style: RadarWidgetStyle

    @Parameter(title: "Weichzeichnen", default: true)
    var smoothing: Bool

    @Parameter(title: "Bewegungspfeile", default: true)
    var motionArrows: Bool

    @Parameter(title: "Regenzellen", default: false)
    var stormCells: Bool
}

// MARK: - Entry view

struct RadarWidgetEntryView: View {
    @Environment(\.widgetRenderingMode) var widgetRenderingMode

    var entry: RadarProvider.Entry

    var body: some View {
        // The composite only matches the widget's aspect approximately, so it fills
        // and gets clipped INSIDE this container — a bare scaledToFill image would
        // grow past the proposed size, drag the frame-time badge along with it, and
        // push it out of the visible top-left corner (shipped once on systemLarge).
        Color.clear
            .overlay {
                if #available(iOSApplicationExtension 18.0, *) {
                    mapImage
                        .widgetAccentedRenderingMode(.accentedDesaturated)
                        .aspectRatio(contentMode: .fill)
                        .contrast(widgetRenderingMode == .accented ? 1.5 : 1)
                } else {
                    mapImage
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                Text(SettingService.formattedTime(entry.frameDate))
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(widgetRenderingMode == .accented ? .gray.opacity(0.3) : .gray.opacity(0.6))
                    .clipShape(.rect(cornerRadius: 5))
                    .widgetAccentable()
                    .padding(15)
            }
            .containerBackground(.clear, for: .widget)
    }

    private var mapImage: Image {
        Image(uiImage: entry.image)
            .resizable()
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
        .description(String(localized: "Regenradar für aktuellen Standort"))
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

#Preview {
    RadarWidgetEntryView(entry: RadarEntry(date: Date(), frameDate: Date(), image: UIImage(named: "rain") ?? UIImage()))
}
