//
//  PrecipitationLockscreenWidget.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 11.04.23.
//

import WidgetKit
import SwiftUI

struct PrecipitationLockScreenView: View {
    var entry: LockscreenProvider.Entry
    @Environment(\.widgetFamily) private var family
    private var units: Units { SettingService.resolvedUnits }
    
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(min(max(entry.precipitationProbability, 0), 100)), in: 0...100) {
                } currentValueLabel: {
                    VStack(spacing: 0) {
                        Text(entry.precipitationProbability, format: .number)
                            .font(.system(size: 18, weight: .semibold))
                        Text(verbatim: "%")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Regenwahrscheinlichkeit \(entry.precipitationProbability) %", comment: "Widget Regen %: Bedienungshilfe"))
            case .accessoryInline:
                HStack {
                    Image(systemName: "umbrella.fill")
                    Text("\(entry.precipitationProbability) % • \(units.precipitationString(entry.precipitation))")
                }
            case .accessoryCorner:
                Image(systemName: "umbrella.fill")
                    .font(.system(size: 24, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .widgetAccentable()
                    .widgetLabel {
                        Text("\(entry.precipitationProbability) % · \(units.precipitationString(entry.precipitation))")
                    }
            default:
                EmptyView()
            }
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(.oscarPlace(entry.cityID))
    }
}

struct PrecipitationLockScreenWidget: Widget {
    let kind: String = "PrecipitationLockScreenWidget"
    
    
    var body: some WidgetConfiguration {
        placeConfiguration(kind: kind, source: LockscreenProvider()) { entry in
            PrecipitationLockScreenView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Regen", comment: "LS Widget Regen"))
        .description(String(localized: "Regenmenge und -wahrscheinlichkeit für die aktuelle Stunde", comment: "LS Widget Regenmenge und -wahrscheinlichkeit"))
        #if os(iOS)
        .supportedFamilies([.accessoryCircular, .accessoryInline])
        #elseif os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
        #endif
    }
}

#Preview("Regen %", as: .accessoryCircular) {
    PrecipitationLockScreenWidget()
} timeline: {
    TemperatureLockScreenEntry(date: .now, temperatureMin: 3, temperatureMax: 9, temperatureNow: 7, icon: "cloud.rain.fill", precipitation: 0.4, precipitationProbability: 70)
    TemperatureLockScreenEntry(date: .now, temperatureMin: 3, temperatureMax: 9, temperatureNow: 7, icon: "sun.max.fill", precipitation: 0, precipitationProbability: 0)
}
