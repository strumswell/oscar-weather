//
//  TemperatureLockscreenWidget.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 10.04.23.
//

import WidgetKit
import SwiftUI

struct TemperatureLockScreenView: View {
    var entry: LockscreenProvider.Entry
    @Environment(\.widgetFamily) private var family
    private var units: Units { SettingService.resolvedUnits }

    private static let temperatureTint = Gradient(colors: [.cyan, .green, .yellow, .orange, .red])

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: entry.temperatureNow, in: entry.temperatureMin...entry.temperatureMax) {
                } currentValueLabel: {
                    Text(units.temperatureString(entry.temperatureNow))
                } minimumValueLabel: {
                    Text("\(units.temperature.rounded(entry.temperatureMin))")
                } maximumValueLabel: {
                    Text("\(units.temperature.rounded(entry.temperatureMax))")
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Self.temperatureTint)
            case .accessoryRectangular:
                TodayRectangularView(entry: entry)
            case .accessoryInline:
                HStack {
                    Image(systemName: entry.icon)
                    Text(units.temperatureString(entry.temperatureNow))
                }
            case .accessoryCorner:
                Text(units.temperatureString(entry.temperatureNow))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .widgetLabel {
                       Gauge(value: entry.temperatureNow, in: entry.temperatureMin...entry.temperatureMax) {
                       } currentValueLabel: {
                           Text("\(units.temperature.rounded(entry.temperatureNow))")
                       } minimumValueLabel: {
                           Text("\(units.temperature.rounded(entry.temperatureMin))")
                       } maximumValueLabel: {
                           Text("\(units.temperature.rounded(entry.temperatureMax))")
                       }
                      .gaugeStyle(LinearCapacityGaugeStyle())
                      .tint(Self.temperatureTint)
                   }
            default:
                EmptyView()
            }
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(.oscarPlace(entry.cityID))
    }
}

private struct TodayRectangularView: View {
    let entry: TemperatureLockScreenEntry
    private var units: Units { SettingService.resolvedUnits }

    private var footnote: String? {
        entry.staleNote ?? entry.rainHeadline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(units.temperatureString(entry.temperatureNow))
                    .font(.system(size: 26, weight: .semibold))
                    .widgetAccentable()
                Text(entry.condition)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Gauge(value: min(max(entry.temperatureNow, entry.temperatureMin), entry.temperatureMax), in: entry.temperatureMin...entry.temperatureMax) {
            } currentValueLabel: {
            } minimumValueLabel: {
                Text(units.temperatureString(entry.temperatureMin))
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(units.temperatureString(entry.temperatureMax))
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .font(.system(size: 11, weight: .semibold))
            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let range = String(localized: "Heute \(units.temperatureString(entry.temperatureMin)) bis \(units.temperatureString(entry.temperatureMax))", comment: "Widget Heute: Tagesspanne")
        return [units.temperatureString(entry.temperatureNow), entry.condition, range, footnote]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

struct TemperatureLockScreenWidget: Widget {
    let kind: String = "TemperatureLockScreenWidget"
    var body: some WidgetConfiguration {
        placeConfiguration(kind: kind, source: LockscreenProvider()) { entry in
            TemperatureLockScreenView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Temperatur", comment: "LS Temperatur"))
        .description(String(localized: "Aktuelle Temperatur und heute zu erwartende Temperaturen", comment: "LS Widget"))
        #if os(iOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        #elseif os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
        #endif
    }
}

#Preview("Heute", as: .accessoryRectangular) {
    TemperatureLockScreenWidget()
} timeline: {
    TemperatureLockScreenEntry(date: .now, temperatureMin: 3, temperatureMax: 9, temperatureNow: 7, icon: "cloud.sun.fill", precipitation: 0, precipitationProbability: 40, condition: "Teils bewölkt", rainHeadline: "Regen ab 14:35")
    TemperatureLockScreenEntry(date: .now, temperatureMin: 3, temperatureMax: 9, temperatureNow: 4, icon: "cloud.fill", precipitation: 0, precipitationProbability: 10, condition: "Bedeckt")
    TemperatureLockScreenEntry(date: .now, temperatureMin: 3, temperatureMax: 9, temperatureNow: 8, icon: "sun.max.fill", precipitation: 0, precipitationProbability: 0, condition: "Klar", staleNote: staleText(.now.addingTimeInterval(-7200), at: .now))
}
