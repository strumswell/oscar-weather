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

    /// Cold-to-warm sweep along the gauge track. Renders in full color on
    /// watch faces; tinted/accented faces flatten it automatically.
    private static let temperatureTint = Gradient(colors: [.cyan, .green, .yellow, .orange, .red])

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: entry.temperatureNow, in: entry.temperatureMin...entry.temperatureMax) {
                } currentValueLabel: {
                    Text("\(Int(round(entry.temperatureNow)))°")
                } minimumValueLabel: {
                    Text("\(Int(round(entry.temperatureMin)))")
                } maximumValueLabel: {
                    Text("\(Int(round(entry.temperatureMax)))")
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Self.temperatureTint)
            case .accessoryInline:
                HStack {
                    Image(systemName: entry.icon)
                    Text("\(Int(round(entry.temperatureNow)))°")
                }
            case .accessoryCorner:
                // The corner slot is ~40 pt; a fixed 30 pt string truncates to "1…".
                Text("\(Int(round(entry.temperatureNow)))°")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
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
