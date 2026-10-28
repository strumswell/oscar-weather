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
    }
}

struct TemperatureLockScreenWidget: Widget {
    let kind: String = "TemperatureLockScreenWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockscreenProvider()) { entry in
            TemperatureLockScreenView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Temperatur", comment: "LS Temperatur"))
        .description(String(localized: "Aktuelle Temperatur und heute zu erwartende Temperaturen", comment: "LS Widget"))
        #if os(iOS)
        .supportedFamilies([.accessoryCircular, .accessoryInline])
        #elseif os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryCorner])
        #endif
    }
}
