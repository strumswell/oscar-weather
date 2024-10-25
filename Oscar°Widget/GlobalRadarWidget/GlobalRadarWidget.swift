//
//  LocalRadarWidget.swift
//  Oscar°
//
//  Created by Philipp Bolte on 13.04.24.
//

import SwiftUI
import WidgetKit

struct GlobalRadarEntryWidget: View {
    var entry: GlobalRadarProvider.Entry
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        ZStack {
            Image(uiImage: entry.image)
                .resizable()
                .aspectRatio(contentMode: .fill)

            Circle()
                .fill(Color.blue)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 2)
                )
                .frame(width: 10, height: 10)
                .shadow(radius: 3)
            
            VStack {
                HStack {
                    Text(dateFormatter.string(from: entry.date))
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.6))
                        .cornerRadius(5)
                    Spacer()
                }
                Spacer()
            }
            .padding(15)
        }
        .containerBackground(.clear, for: .widget)
        .widgetAccentable()
    }
}

struct GlobalRadarWidget: Widget {
    let kind: String = "GlobalRadarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlobalRadarProvider()) { entry in
            GlobalRadarEntryWidget(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName(String(localized: "Regenradar (Global)"))
            .description(String(localized: "Regenradar für aktuellen Standort mit globaler Reichweite"))
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}
