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
    
    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                HStack {
                    Image(systemName: "umbrella.fill")
                    Text("\(entry.precipitationProbability) % • \(entry.precipitation, specifier: "%.1f") mm")
                }
            case .accessoryCorner:
                // Corner anatomy: a square-ish glyph as inner content, the values
                // on the curved label — stacking both inside gets clipped.
                Image(systemName: "umbrella.fill")
                    .font(.system(size: 24, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .widgetAccentable()
                    .widgetLabel {
                        Text("\(entry.precipitationProbability) % · \(entry.precipitation, specifier: "%.1f") mm")
                    }
            default:
                EmptyView()
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct PrecipitationLockScreenWidget: Widget {
    let kind: String = "PrecipitationLockScreenWidget"
    
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockscreenProvider()) { entry in
            PrecipitationLockScreenView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Regen", comment: "LS Widget Regen"))
        .description(String(localized: "Regenmenge und -wahrscheinlichkeit für die aktuelle Stunde", comment: "LS Widget Regenmenge und -wahrscheinlichkeit"))
        #if os(iOS)
        .supportedFamilies([.accessoryInline])
        #elseif os(watchOS)
        .supportedFamilies([.accessoryCorner])
        #endif
    }
}
