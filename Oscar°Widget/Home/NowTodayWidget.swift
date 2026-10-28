//
//  NowTodayWidget.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 03.06.23.
//
import SwiftUI
import WidgetKit

struct NowTodayEntryView: View {
    var entry: HomeProvider.Entry
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var widgetRenderingMode
    private var units: Units { SettingService.resolvedUnits }
    
    var body: some View {
        VStack {
            HStack {
                Text(entry.location)
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
            }
            HStack {
                Text(units.temperatureString(entry.temperatureNow))
                    .font(.system(size: 45))
                    .fontWeight(.regular)
                Spacer()
            }
            HStack {
                Image(systemName: entry.icon)
                Spacer()
            }
            .padding(.bottom, 1)
            HStack {
                Text("H: \(units.temperatureString(entry.temperatureMax))", comment: "Höchste Temperatur")
                    .font(.footnote)
                    .fontWeight(.bold)
                Text("T: \(units.temperatureString(entry.temperatureMin))", comment: "Niedrigste Temperatur")
                    .font(.footnote)
                    .fontWeight(.bold)
                Spacer()
            }
            Spacer()
        }
        .widgetAccentable()
        .padding()
        .foregroundStyle(.white)
        .background {
            entry.backgroundGradient
                .opacity(widgetRenderingMode == .accented ? 0 : 1)
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct NowTodayWidget: Widget {
    let kind: String = "TodayWidget"
    
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeProvider()) { entry in
            NowTodayEntryView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName(String(localized: "Vorhersage"))
        .description(String(localized: "Aktuelle Wetterbedingungen und Temperaturen für heute."))
        .supportedFamilies([.systemSmall])
    }
}

#Preview {
    let previewGradient = LinearGradient(colors: [.sunriseStart, .sunnyDayEnd], startPoint: .top, endPoint: .bottom)
    NowTodayEntryView(entry: HomeEntry(date: Date(), location: "Berlin", temperatureMin: 12.0, temperatureMax: 21.0, temperatureNow: 19.0, icon: "sun.max.fill", backgroundGradient: previewGradient))
}
