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
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.temperatureNow, in: entry.temperatureMin...entry.temperatureMax) {
            } currentValueLabel: {
                Text("\(Int(round(entry.temperatureNow)))")
            } minimumValueLabel: {
                Text("\(Int(round(entry.temperatureMin)))")
            } maximumValueLabel: {
                Text("\(Int(round(entry.temperatureMax)))")
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryInline:
            HStack {
                Image(systemName: entry.icon)
                Text("\(Int(round(entry.temperatureNow)))°")
            }
        case .accessoryCorner:
            Text("\(Int(round(entry.temperatureNow)))°")
                .font(.system(size: 30))
                .widgetLabel {
                   Gauge(value: entry.temperatureNow, in: entry.temperatureMin...entry.temperatureMax) {
                   } currentValueLabel: {
                       Text("\(Int(round(entry.temperatureNow)))")
                   } minimumValueLabel: {
                       Text("\(Int(round(entry.temperatureMin)))")
                   } maximumValueLabel: {
                       Text("\(Int(round(entry.temperatureMax)))")
                   }
                  .gaugeStyle(LinearCapacityGaugeStyle())
               }
        default:
            EmptyView()
        }
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
